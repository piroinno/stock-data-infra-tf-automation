[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $LandingZoneNameRootPath,
    [Parameter()]
    [string]
    $ConfigurationFolder,
    [Parameter()]
    [string]
    $Environment = "dev",
    [Parameter()]
    [string]
    $TerraformPhase = "plan",
    [Parameter()]
    [string]
    $TerraformConfigPlanFilePath = $null,
    [Parameter()]
    [string]
    $TerraformConfigPlanFile = $null,
    [Parameter()]
    [string]
    $TerraformWorkingPath,
    [Parameter()]
    [switch]
    $AutomatedRun
)

begin {
    Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"
    #$env:TF_LOG = "INFO"
    $CURRENT_WORKING_PATH = Get-Location
    trap {
        Write-Verbose "Cleaning up $($MyInvocation.MyCommand.Name)"
        if (Test-Path -Path $TerraformWorkingPath) {
            Write-Verbose "Removing $TerraformWorkingPath"
            Set-Location -Path $CURRENT_WORKING_PATH
            Remove-Item -Path $TerraformWorkingPath -Recurse -Force
        }
    }
    . $PSScriptRoot\Set-PathSlashes.ps1

    if (Test-Path -Path $LandingZoneNameRootPath) {
        Write-Verbose "LandingZoneNameRoot: $LandingZoneNameRootPath"
    }
    else {
        Write-Error "LandingZoneNameRoot: $LandingZoneNameRootPath does not exist"
    }

    if ($AutomatedRun.IsPresent) {
        if ($env:ARM_CLIENT_ID) {
            Write-Verbose "ARM_CLIENT_ID is Set"
        }
        else {
            Write-Host $env:ARM_CLIENT_ID
            Write-Error "ARM_CLIENT_ID does not exist"
        }

        if ($env:ARM_CLIENT_SECRET) {
            Write-Verbose "ARM_CLIENT_SECRET is Set"
        }
        else {
            Write-Error "ARM_CLIENT_SECRET does not exist"
        }

        if ($env:ARM_TENANT_ID) {
            Write-Verbose "ARM_TENANT_ID is Set"
        }
        else {
            Write-Error "ARM_TENANT_ID does not exist"
        }

        if ($env:ARM_SUBSCRIPTION_ID) {
            Write-Verbose "ARM_SUBSCRIPTION_ID is Set"
        }
        else {
            Write-Error "ARM_SUBSCRIPTION_ID does not exist"
        }
        $env:TF_IS_AUTOMATION = "true"
        az login --service-principal -u $env:ARM_CLIENT_ID -p $env:ARM_CLIENT_SECRET --tenant $env:ARM_TENANT_ID
        az account set --subscription $env:ARM_SUBSCRIPTION_ID
    }
    else {
        if ((Get-AzContext -ErrorAction 0)) {
            Write-Verbose "Azure Context is Set. Skipping Azure Login"
        }
        else {
            Write-Error "Azure Context is not Set. Please login to Azure"
        }
        Write-Verbose "Automation is not configured"
    }
    $TF_LOCK_TIMEOUT = "300s"
    $TF_WORKING_FOLDER = (New-Guid).Guid
    Write-Verbose "Setting TerraformConfigPath"
    $TerraformConfigPath = Set-PathSlashes(("{0}/{1}" -f $LandingZoneNameRootPath, $ConfigurationFolder))
    if (Test-Path -Path $TerraformConfigPath) {
        Write-Verbose "TerraformConfigPath: $TerraformConfigPath"
    }
    else {
        Write-Error "TerraformConfigPath: $TerraformConfigPath does not exist"
    }

    $TerraformTfVarsPath = Set-PathSlashes(("{0}/{1}/envs/{2}" -f $LandingZoneNameRootPath, $ConfigurationFolder, $Environment))
    if (Test-Path -Path $TerraformTfVarsPath) {
        Write-Verbose "TerraformTfVarsPath: $TerraformTfVarsPath"
    }
    else {
        Write-Error "TerraformTfVarsPath: $TerraformTfVarsPath does not exist"
    }

    $TerraformTfBackendPath = Set-PathSlashes(("{0}/{1}/envs/{2}/{3}" -f $LandingZoneNameRootPath, $ConfigurationFolder, $Environment, "tf.backend"))
    if (Test-Path -Path $TerraformTfBackendPath) {
        Write-Verbose "TerraformTfBackendPath: $TerraformTfBackendPath"
    }
    else {
        Write-Error "TerraformTfBackendPath: $TerraformTfBackendPath does not exist"
    }

    New-Item -Path $TerraformWorkingPath -ItemType Directory -Force
    Set-Location -Path $TerraformWorkingPath
    Write-Verbose "TerraformWorkingPath: $TerraformWorkingPath"
    Write-Verbose "Copying Resource Files from $TerraformConfigPath to $TerraformWorkingPath"
    Copy-Item -Path (Set-PathSlashes(("{0}\*" -f $TerraformConfigPath))) -Destination $TerraformWorkingPath -Exclude $TF_WORKING_FOLDER, "envs", ".terraform" -Force -Verbose

    Write-Verbose "Copying Terraform Variables from $TerraformTfVarsPath to $TerraformWorkingPath"
    Copy-Item -Path (Set-PathSlashes(("{0}\*" -f $TerraformTfVarsPath))) -Destination $TerraformWorkingPath -Exclude $TF_WORKING_FOLDER -Force -Verbose
    
    Write-Verbose "Listing Files in $TerraformWorkingPath"
    Get-Item -Path (Set-PathSlashes(("{0}\*" -f $TerraformWorkingPath)))

    # Adding taint feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tftaint")))) -eq $true) {
        $TaintedResources = Get-Content Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tftaint"))
    }

    # Adding import feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport")))) -eq $true) {
        $ImportedResources = Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport"))
    }

    # Adding delete feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport")))) -eq $true) {
        $DeletedResources = Get-Content (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport")))
    }
}

process {
    if ($TerraformPhase -in "plan", "apply", "destroy") {
        Write-Verbose "Starting Terraform Init"
        Invoke-Expression("terraform init -backend-config=$TerraformTfBackendPath -input=false -lock-timeout=$TF_LOCK_TIMEOUT")
    }
    
    switch ($TerraformPhase) {
        plan {
            foreach ($DeletedResource in $DeletedResources) {
                Write-Verbose "Deleting $DeletedResource"
                Invoke-Expression("terraform state $DeletedResource -input=false -lock-timeout=$TF_LOCK_TIMEOUT")
            }
            foreach ($TaintedResource in $TaintedResources) {
                Write-Verbose "Tainting $TaintedResource"
                Invoke-Expression("terraform taint $TaintedResource -input=false -lock-timeout=$TF_LOCK_TIMEOUT")
            }
            foreach ($ImportedResource in $ImportedResources) {
                Write-Verbose "Importing $ImportedResource"
                Invoke-Expression("terraform import $($ImportedResource -split " ") -input=false -lock-timeout=$TF_LOCK_TIMEOUT")
            }
            Write-Verbose "Starting Terraform Plan"
            if ($TerraformConfigPlanFilePath -and $TerraformConfigPlanFile) {
                $TerraformConfigPlan = "-out=$TerraformConfigPlanFile"
                Write-Verbose "Terraform Plan File: $TerraformConfigPlanFilePath"
            }
            Invoke-Expression("terraform plan -lock-timeout=$TF_LOCK_TIMEOUT $TerraformConfigPlan")
            break
        }
        apply {
            Invoke-Expression("terraform apply $TerraformConfigPlanFilePath -auto-approve -lock-timeout=$TF_LOCK_TIMEOUT")
            Copy-Item -Path ((Set-PathSlashes((".\{0}" -f $TerraformConfigPlanFile)))) -Destination ((Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPlanFilePath, $TerraformConfigPlanFile)))) -Force -Verbose
            break
        }
        default {
            Write-Verbose "Starting Terraform Validate"
            Invoke-Expression("terraform validate")
            break
        }
    }
    
    if ( $LASTEXITCODE -ne 0) {
        Write-Verbose "Cleaning up $($MyInvocation.MyCommand.Name)"
        if (Test-Path -Path $TerraformWorkingPath) {
            Write-Verbose "Removing $TerraformWorkingPath"
            Set-Location -Path $CURRENT_WORKING_PATH
            Remove-Item -Path $TerraformWorkingPath -Recurse -Force
        }
        Write-Error "Error found in deploying $TerraformWorkingPath. Exit code is: $LASTEXITCODE";
    }
    else {
        Write-Verbose "Terraform complete for $TerraformWorkingPath";
    }
}

end {
    Write-Verbose "Cleaning up $($MyInvocation.MyCommand.Name)"
    if (Test-Path -Path $TerraformWorkingPath) {
        Write-Verbose "Removing $TerraformWorkingPath"
        Set-Location -Path $CURRENT_WORKING_PATH
        Remove-Item -Path $TerraformWorkingPath -Recurse -Force
    }
    Write-Verbose "Ending $($MyInvocation.MyCommand.Name)"
}