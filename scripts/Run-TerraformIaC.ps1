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
        Set-Location -Path $CURRENT_WORKING_PATH
    }
    . $PSScriptRoot\Set-PathSlashes.ps1

    if (Test-Path -Path $LandingZoneNameRootPath) {
        Write-Verbose "LandingZoneNameRootPath: $LandingZoneNameRootPath"
    }
    else {
        Write-Error "LandingZoneNameRootPath: $LandingZoneNameRootPath does not exist"
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
        az login --service-principal --allow-no-subscriptions -u $env:ARM_CLIENT_ID -p $env:ARM_CLIENT_SECRET --tenant $env:ARM_TENANT_ID
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
    $TF_WORKING_TEMP_PATH = $TerraformWorkingPath
    Write-Verbose "Setting TerraformConfigPath"
    $TerraformConfigPath = (Set-PathSlashes(("{0}/{1}" -f $LandingZoneNameRootPath, $ConfigurationFolder)))
    if (Test-Path -Path $TerraformConfigPath) {
        Write-Verbose "TerraformConfigPath: $TerraformConfigPath"
    }
    else {
        Write-Error "TerraformConfigPath: $TerraformConfigPath does not exist"
    }

    Write-Verbose "Setting TerraformTfVarsPath"
    $TerraformTfVarsPath = (Set-PathSlashes(("{0}/envs/{1}" -f $TerraformConfigPath, $Environment)))
    Get-ChildItem $TerraformTfVarsPath -Recurse
    if (Test-Path -Path $TerraformTfVarsPath) {
        Write-Verbose "TerraformTfVarsPath: $TerraformTfVarsPath"
    }
    else {
        Write-Error "TerraformTfVarsPath: $TerraformTfVarsPath does not exist"
    }

    Write-Verbose "Setting TerraformTfBackendPath"
    $TerraformTfBackendPath = (Set-PathSlashes(("{0}/tf.backend" -f $TerraformTfVarsPath)))
    if (Test-Path -Path $TerraformTfBackendPath) {
        Write-Verbose "TerraformTfBackendPath: $TerraformTfBackendPath"
    }
    else {
        Write-Error "TerraformTfBackendPath: $TerraformTfBackendPath does not exist"
    }

    Write-Verbose "Setting working directory to $TF_WORKING_TEMP_PATH"
    New-Item -Path $TF_WORKING_TEMP_PATH -ItemType Directory -Force
    Set-Location -Path $TF_WORKING_TEMP_PATH

    Write-Verbose "Copying Resource Files from $TerraformConfigPath to $TF_WORKING_TEMP_PATH"
    Copy-Item -Path (Set-PathSlashes(("{0}\*" -f $TerraformConfigPath))) -Destination $TF_WORKING_TEMP_PATH -Exclude "envs", ".terraform" -Force -Verbose

    Write-Verbose "Copying Terraform Variables from $TerraformTfVarsPath to $TF_WORKING_TEMP_PATH"
    Copy-Item -Path (Set-PathSlashes(("{0}\*" -f $TerraformTfVarsPath))) -Destination $TF_WORKING_TEMP_PATH -Force -Verbose
    
    Write-Verbose "Listing Files in $TF_WORKING_TEMP_PATH"
    Get-Item -Path (Set-PathSlashes(("{0}\*" -f $TF_WORKING_TEMP_PATH)))

    # Adding taint feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tftaint"))))) {
        $TaintedResources = Get-Content Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tftaint"))
    }

    # Adding import feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport"))))) {
        $ImportedResources = Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport"))
    }

    # Adding delete feature
    if ((Test-Path -Path (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport"))))) {
        $DeletedResources = Get-Content (Set-PathSlashes(("{0}/{1}" -f $TerraformConfigPath, ".tfstateimport")))
    }
}

process {
    if ($TerraformPhase -in "plan", "apply", "destroy") {
        Write-Verbose "Starting Terraform Init"
        Invoke-Expression("terraform init -backend-config=`"$TerraformTfBackendPath`" -input=false -lock-timeout=$TF_LOCK_TIMEOUT")
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
            Write-Verbose "Planning Terraform to $TerraformConfigPlanFile"
            Invoke-Expression("terraform plan -lock-timeout=$TF_LOCK_TIMEOUT $TerraformConfigPlan")
            break
        }
        apply {
            Write-Verbose "Starting Terraform Apply"
            Invoke-Expression("terraform apply $((Set-PathSlashes(("./{0}" -f $TerraformConfigPlanFile)))) -auto-approve -lock-timeout=$TF_LOCK_TIMEOUT")
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
        Set-Location -Path $CURRENT_WORKING_PATH
        Write-Error "Error found in deploying $TF_WORKING_TEMP_PATH. Exit code is: $LASTEXITCODE";
    }
    else {
        Write-Verbose "Terraform complete for $TF_WORKING_TEMP_PATH";
    }
}

end {
    Set-Location -Path $CURRENT_WORKING_PATH
    Write-Verbose "Ending $($MyInvocation.MyCommand.Name)"
}