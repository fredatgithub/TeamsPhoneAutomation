﻿# Version: 2.3.9

param
(
    [Parameter (Mandatory = $false)]
    [object] $WebhookData
)

if ($host.Name -eq "Visual Studio Code Host") {

    $localTestMode = $true

}

else {

    $localTestMode = $false



}

$syncTeamsNumbersToEntraIdBusinessPhones = $true

function Get-AllSPOListItems {
    param (
        [Parameter(Mandatory = $true)][string]$ListId
    )
    
    # Get existing list items
    $sharePointListItems = @()

    $querriedItems = (Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($ListId)/items?expand=fields")
    $sharePointListItems += $querriedItems.value.fields
    
    if ($querriedItems.'@odata.nextLink') {
    
        Write-Output "List contains more than $($querriedItems.value.Count) items. Querrying additional items..."
    
        do {
    
            $querriedItems = (Invoke-RestMethod -Method Get -Headers $Header -Uri $querriedItems.'@odata.nextLink')
            $sharePointListItems += $querriedItems.value.fields
                
        } until (
            !$querriedItems.'@odata.nextLink'
        )
    
    }
    
    else {
    
        Write-Output "All items were retrieved in the first request."
    
    }
    
    Write-Output "Finished retrieving $($sharePointListItems.Count) items."


}

switch ($localTestMode) {
    $true {

        # Local Environment

        $runBookDateTime = (Get-Date).ToUniversalTime()
        Write-Output "Runbook start time: $runBookDateTime (UTC)"

        # Import external functions
        . .\Functions\Connect-MsTeamsServicePrincipal.ps1
        . .\Functions\Connect-MgGraphHTTP.ps1
        . .\Functions\Get-CountryFromPrefix.ps1
        . .\Functions\Get-CsOnlineNumbers.ps1

        # Import variables
        $MsListName = "Teams Phone Number Overview Demo V14"
        $TenantId = Get-Content -Path .\.local\TenantId.txt
        $AppId = Get-Content -Path .\.local\AppId.txt
        $AppSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-Content -Path .\.local\AppSecret.txt | ConvertTo-SecureString))) | Out-String
        $groupId = Get-Content -Path .\.local\GroupId.txt

        # Import Direct Routing numbers
        $allDirectRoutingNumbers = Import-Csv -Path .\Resources\DirectRoutingNumbers-V2.csv -Encoding UTF8 -Delimiter ";"

        # Get previous total number count
        $totalNumberCount = Get-Content -Path .\.local\TeamsPhoneNumberOverview_TotalNumberCount.txt
        
    }

    $false {

        # Azure Automation

        $runBookDateTime = Get-Date
        Write-Output "Runbook start time: $runBookDateTime (UTC)"

        # Import external functions
        . .\Connect-MsTeamsServicePrincipal.ps1
        . .\Connect-MgGraphHTTP.ps1
        . .\Get-CountryFromPrefix.ps1
        . .\Get-CsOnlineNumbers.ps1

        # Import variables        
        $MsListName = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_MsListName"
        $TenantId = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_TenantId"
        $AppId = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_AppId"
        $AppSecret = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_AppSecret"
        $groupId = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_GroupId"

        # Import Direct Routing numbers
        $allDirectRoutingNumbers = (Get-AutomationVariable -Name "TeamsPhoneNumberOverview_DirectRoutingNumbers").Replace("'", "") | ConvertFrom-Json

        # Get previous total number count
        $totalNumberCount = Get-AutomationVariable -Name "TeamsPhoneNumberOverview_TotalNumberCount"

        # Get webhook data
        $runbookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
        
        $runbookBody

        if (!$runbookBody) {

            Write-Output "Sleeping for 120s to simulate job already running..."
            Start-Sleep -Seconds 120

        }

        # Define Azure environment variables
        $automationAccountName = "mzz-automation-account-014"
        $resourceGroupName = "mzz-rmg-013"
        $pythonRunbookName = "Format-TeamsPhoneNumbers"

        # Connect to Azure environment
        . Connect-AzAccount -Identity -TenantId $TenantId

        $queuedAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Queued"
        $startingAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Starting"
        $runningAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Running"

        if ($startingAutomationJobs) {

            foreach ($startingAutomationJob in $startingAutomationJobs) {

                $timeElapsedSinceJobStart = $runBookDateTime - $startingAutomationJob.CreationTime.UtcDateTime

                if ($timeElapsedSinceJobStart.TotalMinutes -gt 20) {

                    Write-Output "Starting job $($startingAutomationJob.JobId) is stuck in starting state since more than 20 minutes. Job will be stopped."

                    Stop-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -JobId $startingAutomationJob.JobId

                }

            }

            Write-Output "Sleeping for 30s..."

            Start-Sleep -Seconds 30

            $queuedAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Queued"
            $startingAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Starting"
            $runningAutomationJobs = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName "TeamsPhoneNumberOverview" -Status "Running"

        }

        if ($queuedAutomationJobs -or $startingAutomationJobs -or $runningAutomationJobs.Count -gt 1) {

            Write-Output "Job is already running. Job will be stopped."

            $messageBody = @{
                MessageId         = "$($runbookBody.MessageId)"
                CompletedDateTime = (Get-Date -Format "o")
                StartDateTime     = (Get-Date -Date $($runbookBody.StartDateTime) -Format "o")
                TriggerPassword   = "ExamplePassword"
                TriggeredBy       = "$($runbookBody.TriggeredBy)"
                TriggeredByUpn    = "$($runbookBody.TriggeredByUpn)"
                JobAborted        = $true
            }
            
            $flowURI = "https://prod-226.westeurope.logic.azure.com:443/workflows/1a8d77007d6441a787d83ffe04be3417/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=YyoNrQRn2ZhSmoG1UvtG5oVjL_EtSSc35x-_ZcWV7ow"

            Invoke-RestMethod -Uri $flowURI -Method POST -ContentType "application/json" -Body ($messageBody | ConvertTo-Json) -ErrorAction Stop

            Start-Sleep -Seconds 5

            exit

        }

    }
    Default {}
}

. Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

. Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

$checkGetCsTenant = Get-CsTenant -ErrorAction SilentlyContinue
$checkGetCsOnlineUser = Get-CsOnlineUser -ResultSize 1 -ErrorAction SilentlyContinue
$checkGetCsPhoneNumberAssignment = Get-CsPhoneNumberAssignment -Top 1 -ErrorAction SilentlyContinue

if ($checkGetCsTenant -and $checkGetCsOnlineUser -and $checkGetCsOnlineUser) {

    Write-Output "All Microsoft Teams PowerShell connection checks were successful."

}

else {

    Write-Output "Not all Microsoft Teams PowerShell connection checks were successful. Exiting runbook."
    exit

}

# Get existing SharePoint lists for group id
$sharePointSite = (Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/sites/root")

$existingSharePointLists = (Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists").value

# $userInformationListId = (Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists?`$filter=displayName eq '$localizedUserInformationList'").value.id

# From: https://stackoverflow.com/questions/61143146/how-to-get-user-from-user-field-lookupid
$userInformationListId = ((Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists?select=id,name,system").value | Where-Object { $_.name -eq "users" }).id

# Retrieve all list items
. Get-AllSPOListItems -ListId $userInformationListId
$userInformationList = $sharePointListItems

$userLookupIds = $userInformationList | Select-Object Username, UserSelection

if ($existingSharePointLists.name -contains $MsListName) {

    Write-Output "A list with the name $MsListName already exists in site $($sharePointSite.name). No new list will be created."

    $sharePointListId = ($existingSharePointLists | Where-Object { $_.Name -eq $MsListName }).id

}

else {

    Write-Output "A list with the name $MsListName does not exist in site $($sharePointSite.name). A new list will be created."

    switch ($localTestMode) {
        $true {
    
            # Local Environment
    
            $createListJson = (Get-Content -Path .\Resources\CreateList-V2.json).Replace("Name Placeholder", $MsListName)
            
        }
    
        $false {
    
            # Azure Automation
    
            $createListJson = (Get-AutomationVariable -Name "TeamsPhoneNumberOverview_CreateList").Replace("Name Placeholder", $MsListName).Replace("'", "")

        }
        Default {}
    }
    
    $newSharePointList = Invoke-RestMethod -Method Post -Headers $Header -ContentType "application/json" -Body $createListJson -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists"

    $sharePointListId = $newSharePointList.id

}

# Get all items from SharePoint list (phone numbers)
. Get-AllSPOListItems -ListId $sharePointListId

if ($sharePointListItems) {

    # Unassign numbers

    foreach ($reservedNumber in ($sharePointListItems | Where-Object { $_.Status -eq "Remove Pending" -and $_.User_x0020_Principal_x0020_Name -ne "Unassigned" })) {

        Write-Output "Trying to remove the number $($reservedNumber.Title) from user $($reservedNumber.User_x0020_Principal_x0020_Name)..."

        Remove-CsPhoneNumberAssignment -Identity $reservedNumber.User_x0020_Principal_x0020_Name -RemoveAll

        # Write-Output "Sleeping for 30s..."

        # Start-Sleep 30

    }

    # Assign reserved numbers

    foreach ($reservedNumber in ($sharePointListItems | Where-Object { ($_.Status -match "Reserved" -or $_.Status -eq "Assignment Error") -and ($_.UserProfileLookupId -ne $null -or $_.User_x0020_Principal_x0020_Name -ne "Unassigned") })) {

        $userPrincipalName = ($userLookupIds | Where-Object { $_.UserSelection -eq $reservedNumber.UserProfileLookupId }).Username

        if (!$userPrincipalName) {

            Write-Output "User with lookup id $($reservedNumber.UserProfileLookupId) is not available in the lookup table yet. Trying to get user principal name from list."

            if ($reservedNumber.User_x0020_Principal_x0020_Name -ne "Unassigned" -and $null -ne $reservedNumber.User_x0020_Principal_x0020_Name) {

                $userPrincipalName = $reservedNumber.User_x0020_Principal_x0020_Name

            }

            else {

                $userPrincipalName = $null

            }

        }

        if ($userPrincipalName) {

            $checkCsOnlineUser = (Get-CsOnlineUser -Identity $userPrincipalName)

            if ($checkCsOnlineUser) {

                if ($checkCsOnlineUser.LineURI) {

                    $checkCsOnlineUserLineURI = $checkCsOnlineUser.LineURI.Replace("tel:", "")

                    if ($checkCsOnlineUserLineURI -ne $reservedNumber.Title) {

                        Write-Output "User $userPrincipalName already has $checkCsOnlineUserLineURI assigned. Number will be removed and replaced with $($reservedNumber.Title)"
    
                        Remove-CsPhoneNumberAssignment -Identity $userPrincipalName -RemoveAll
    
                    }
    
                    if ($checkCsOnlineUserLineURI -eq $reservedNumber.Title) {
    
                        Write-Output "Reserved number $($reservedNumber.Title) is already assigned to $userPrincipalName."

                        $assignReservedNumber = $false
    
                    }

                    else {

                        $assignReservedNumber = $true
    
                    }    

                }

                else {

                    $assignReservedNumber = $true

                }

            }

            else {

                Write-Output "User $userPrincipalName is not available in the tenant. Number $($reservedNumber.Title) will not be assigned."

                ($sharePointListItems | Where-Object { $_.Title -eq $reservedNumber.Title }).Status = "Assignment Error"

                $assignReservedNumber = $false

            }

        }

        else {

            Write-Output "User $userPrincipalName is not available in the tenant. Number $($reservedNumber.Title) will not be assigned."

            ($sharePointListItems | Where-Object { $_.Title -eq $reservedNumber.Title }).Status = "Assignment Error"

            $assignReservedNumber = $false

        }

        if ($assignReservedNumber -eq $true) {

            Write-Output "Checking License and Usage Location for user $userPrincipalName..."

            switch ($reservedNumber.Number_x0020_Type) {
                CallingPlan {

                    # Check if user has Calling Plan license, no need for Teams Phone Standard Check because CP requires Teams Phone Standard
                    if ($checkCsOnlineUser.FeatureTypes -contains "CallingPlan") {

                        $licenseCheckSuccess = $true

                    }

                    else {

                        $licenseCheckSuccess = $false

                    }

                    if ($checkCsOnlineUser.UsageLocation -eq $reservedNumber.Country) {

                        $usageLocationCheck = $true

                    }

                    else {

                        $usageLocationCheck = $false

                    }

                    $assignVoiceRoutingPolicy = $false

                }

                OperatorConnect {

                    # Check if user has Teams Phone Standard License
                    if ($checkCsOnlineUser.FeatureTypes -contains "PhoneSystem") {

                        $licenseCheckSuccess = $true

                        if ($checkCsOnlineUser.UsageLocation -eq $reservedNumber.Country) {

                            $usageLocationCheck = $true

                        }

                        else {

                            $usageLocationCheck = $false

                        }


                    }

                    else {

                        $licenseCheckSuccess = $false

                    }

                    $assignVoiceRoutingPolicy = $false

                }

                DirectRouting {

                    # Check if user has Teams Phone Standard License
                    if ($checkCsOnlineUser.FeatureTypes -contains "PhoneSystem") {

                        $licenseCheckSuccess = $true

                        $usageLocationCheck = $true

                    }

                    else {

                        $licenseCheckSuccess = $false

                    }

                    $assignVoiceRoutingPolicy = $true

                }
                Default {}
            }

            # Trying to fix usage location errors
            if ($usageLocationCheck -eq $false) {

                # Usage location does not match phone number
                $patchBody = @{UsageLocation = $($reservedNumber.Country) } | ConvertTo-Json

                Invoke-RestMethod -Method Patch -Headers $Header -Uri "https://graph.microsoft.com/v1.0/users/$($checkCsOnlineUser.Identity)" -ContentType "application/json" -Body $patchBody
                
                if ($?) {

                    do {
                        Write-Output "Sleeping for 20s..."

                        Start-Sleep 20

                        $checkCsOnlineUser = Get-CsOnlineUser -Identity $checkCsOnlineUser.Identity
                    } until (
                        $checkCsOnlineUser.UsageLocation -eq $reservedNumber.Country
                    )

                    Write-Output "Usage location has been successfully changed to $($checkCsOnlineUser.UsageLocation) for user $($checkCsOnlineUser.UserPrincipalName)"

                    $usageLocationCheck = $true
                }

                else {

                    Write-Output "Error while trying to change usage location to $($checkCsOnlineUser.UsageLocation) for user $($checkCsOnlineUser.UserPrincipalName)"

                    $usageLocationCheck = $false

                }

            }

            if ($licenseCheckSuccess -eq $true -and $usageLocationCheck -eq $true) {

                Write-Output "License and Usage Location checks for user $userPrincipalName are successful."
                Write-Output "Trying to assign reserved number $($reservedNumber.Title) to user $userPrincipalName..."

                Set-CsPhoneNumberAssignment -Identity $userPrincipalName -PhoneNumberType $reservedNumber.Number_x0020_Type -PhoneNumber $reservedNumber.Title

                if ($assignVoiceRoutingPolicy -eq $true) {

                    $phoneNumber = $reservedNumber.Title

                    . Get-CountryFromPrefix

                    Write-Output "$($reservedNumber.Title) is a Direct Routing Number. Voice Routing Policy $voiceRoutingPolicy will be assigned."

                    Grant-CsOnlineVoiceRoutingPolicy -Identity $userPrincipalName -PolicyName $voiceRoutingPolicy

                }

            }

            # License issue
            else {

                if ($licenseCheckSuccess -eq $false) {

                    Write-Output "User $userPrincipalName is missing the license for $($reservedNumber.Number_x0020_Type) assignment."

                }

                if ($usageLocationCheck -eq $false) {

                    Write-Output "Usage Location of $userPrincipalName is $($checkCsOnlineUser.UsageLocation) and does not match phone number country $($reservedNumber.Country)."

                }

                ($sharePointListItems | Where-Object { $_.Title -eq $reservedNumber.Title }).Status = "Assignment Error"

            }

        }

    }
    
}

# Add leading plus ("+") to all numbers
$allDirectRoutingNumbers | ForEach-Object { $_.PhoneNumber = "+$($_.PhoneNumber)" }

# Get CsOnline Numbers
$allCsOnlineNumbers = . Get-CsOnlineNumbers

# All phone numbers, CP, OC and DR
$allTelephoneNumbers = $allCsOnlineNumbers.TelephoneNumber
$allTelephoneNumbers += $allDirectRoutingNumbers.PhoneNumber
$allTelephoneNumbers = $allTelephoneNumbers | Sort-Object -Unique
$allTelephoneNumbersCount = $allTelephoneNumbers.Count

switch ($localTestMode) {
    $true {

        # Check if total number count is not the same
        if ($allTelephoneNumbersCount -ne $totalNumberCount) {

            # Save all numbers as string to local text file

            $allTelephoneNumbers = $allTelephoneNumbers -join ";"

            if ($allTelephoneNumbers[-1] -eq ";") {

                $allTelephoneNumbers = $allTelephoneNumbers.Substring(0, $allTelephoneNumbers.Length - 1)

            }

            Set-Content -Path .\.local\TeamsPhoneNumberOverview_AllCsOnlineNumbers.txt -Value $allTelephoneNumbers

            Write-Output "All telephone numbers set to local text file."

            # Update total number count
            Set-Content -Path .\.local\TeamsPhoneNumberOverview_TotalNumberCount.txt -Value ($allTelephoneNumbersCount)

            Write-Output "Total number count in local text file updated."

            Write-Output "using python to prettify numbers..."

            & python ".\Functions\Format-TeamsPhoneNumbers-Local.py"
        
        }

        else {

            Write-Output "Number count is the same as in previous job. Prettified numbers won't be updated."

        }

        # Import prettified numbers from local text file
        $prettyNumbers = (Get-Content -Path .\.local\TeamsPhoneNumberOverview_PrettyNumbers.txt).Replace("'", "") | ConvertFrom-Json

    }
    $false {

        # Check if total number count is not the same
        if ($allTelephoneNumbersCount -ne $totalNumberCount) {

            # Save all numbers as string to automation variable

            $allTelephoneNumbers = $allTelephoneNumbers -join ";"

            if ($allTelephoneNumbers[-1] -eq ";") {

                $allTelephoneNumbers = $allTelephoneNumbers.Substring(0, $allTelephoneNumbers.Length - 1)

            }

            Set-AutomationVariable -Name "TeamsPhoneNumberOverview_AllCsOnlineNumbers" -Value $allTelephoneNumbers

            Write-Output "All telephone numbers set to automation variable."

            # Update total number count
            Set-AutomationVariable -Name "TeamsPhoneNumberOverview_TotalNumberCount" -Value ($allTelephoneNumbersCount)

            Write-Output "Total number count automation variable updated."

            Write-Output "Starting python runbook"

            Start-AzAutomationRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -RunbookName $pythonRunbookName -MaxWaitSeconds 1000 -Wait

            Write-Output "Python runbook finished."

        }

        else {

            Write-Output "Number count is the same as in previous job. Prettified numbers won't be updated."

        }

        # Import prettified numbers from automation variable
        $prettyNumbers = (Get-AutomationVariable -Name "TeamsPhoneNumberOverview_PrettyNumbers").Replace("'", "") | ConvertFrom-Json

    }
    Default {}
}

# Get all Teams users which have a phone number assigned
# $allTeamsPhoneUsers = Get-CsOnlineUser -Filter "LineURI -ne `$null" -ResultSize 9999
$allTeamsPhoneUsers = Get-CsOnlineUser -Filter "(FeatureTypes -contains 'PhoneSystem') -or (FeatureTypes -contains 'VoiceApp')" -ResultSize 9999 | Select-Object Identity, UserPrincipalName, DisplayName, LineURI, FeatureTypes
$allTeamsPhoneUserDetails = @()

$userCounter = 1

foreach ($teamsPhoneUser in $allTeamsPhoneUsers) {

    if ($userCounter % 100 -eq 0) {

        Write-Output "Working on $userCounter/$($allTeamsPhoneUsers.Count)..."

    }

    # Check if user has a LineURI

    if (!$teamsPhoneUser.LineUri) {

        $teamsPhoneUser = Get-CsOnlineUser -Identity $teamsPhoneUser.Identity | Select-Object Identity, UserPrincipalName, DisplayName, LineURI, FeatureTypes

    }

    if ($teamsPhoneUser.LineUri) {

        $teamsPhoneUserDetails = New-Object -TypeName psobject

        $teamsPhoneUserLineUriPrettyIndex = $prettyNumbers.original.IndexOf($teamsPhoneUser.LineUri.Replace("tel:", ""))

        if ($teamsPhoneUserLineUriPrettyIndex -eq -1) {

            $teamsPhoneUserLineUriPretty = "N/A"

        }

        else {

            $teamsPhoneUserLineUriPretty = $prettyNumbers.formatted[$teamsPhoneUserLineUriPrettyIndex]

            if ($syncTeamsNumbersToEntraIdBusinessPhones -eq $true) {

                $entraIdUser = Invoke-RestMethod -Method Get -Headers $Header -Uri "https://graph.microsoft.com/v1.0/users/$($teamsPhoneUser.Identity)?`$select=id,userPrincipalName,businessPhones"

                if ($entraIdUser.businessPhones[0] -ne $teamsPhoneUserLineUriPretty) {

                    Write-Output "User $($teamsPhoneUser.UserPrincipalName) has a different phone number in Entra ID: '$($entraIdUser.businessPhones[0])'. Trying to update it to $teamsPhoneUserLineUriPretty..."

                    $body = @{businessPhones = @($teamsPhoneUserLineUriPretty) }

                    Invoke-RestMethod -Method PATCH -Headers $Header -Body ($body | ConvertTo-Json) -ContentType "application/json" -Uri "https://graph.microsoft.com/v1.0/users/$($entraIdUser.id)"

                    if ($?) {

                        Write-Output "Phone number has been successfully changed to $($teamsPhoneUserLineUriPretty) for user $($teamsPhoneUser.UserPrincipalName)"

                    }

                    else {

                        Write-Output "Error while trying to change phone number to $($teamsPhoneUserLineUriPretty) for user $($teamsPhoneUser.UserPrincipalName)"

                    }

                }

            }

        }

        if ($teamsPhoneUser.FeatureTypes -contains "VoiceApp") {

            $teamsPhoneUserType = "Resource Account"

        }

        else {

            $teamsPhoneUserType = "User Account"

        }

        $phoneNumber = $teamsPhoneUser.LineUri.Replace("tel:", "")

        if ($teamsPhoneUser.LineUri -match ";") {

            $lineUri = $teamsPhoneUser.LineUri.Split(";")[0]
            $extension = $teamsPhoneUser.LineUri.Split(";")[-1]

            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Title" -Value $lineUri.Replace("tel:", "")
            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $teamsPhoneUserLineUriPretty
            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value $extension

        }

        else {

            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Title" -Value $teamsPhoneUser.LineUri.Replace("tel:", "")
            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $teamsPhoneUserLineUriPretty
            $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value "N/A"
        }

        if ($allCsOnlineNumbers.TelephoneNumber -contains $phoneNumber) {

            $matchingCsOnlineNumber = ($allCsOnlineNumbers | Where-Object { $_.TelephoneNumber -eq ($teamsPhoneUser.LineUri).Replace("tel:", "") })

            $operatorName = $matchingCsOnlineNumber.PstnPartnerName

            $numberType = $matchingCsOnlineNumber.NumberType

            if ($numberType -eq "DirectRouting") {

                $directRoutingNumberIndex = $allDirectRoutingNumbers.PhoneNumber.IndexOf($phoneNumber)
                $operatorName = $allDirectRoutingNumbers.Operator[$directRoutingNumberIndex]

            }

            $city = $matchingCsOnlineNumber.City

            if ($matchingCsOnlineNumber.IsoCountryCode) {
                
                $country = $matchingCsOnlineNumber.IsoCountryCode

            }

            else {

                $country = . Get-CountryFromPrefix

            }

        }

        else {

            $assignedDirectRoutingNumberCity = ($allCsOnlineNumbers | Where-Object { $_.TelephoneNumber -eq $phoneNumber }).City

            $directRoutingNumberIndex = $allDirectRoutingNumbers.PhoneNumber.IndexOf($phoneNumber)
            $operatorName = $allDirectRoutingNumbers.Operator[$directRoutingNumberIndex]

            $numberType = "DirectRouting"
            $city = $assignedDirectRoutingNumberCity

            $country = . Get-CountryFromPrefix

        }

        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Status" -Value "Assigned"
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Number_x0020_Type" -Value $numberType
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Operator" -Value $operatorName
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "City" -Value $city
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Country" -Value $country

        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Name" -Value $teamsPhoneUser.DisplayName
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Principal_x0020_Name" -Value $teamsPhoneUser.UserPrincipalName
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "Account_x0020_Type" -Value $teamsPhoneUserType
        $teamsPhoneUserDetails | Add-Member -MemberType NoteProperty -Name "UserId" -Value $teamsPhoneUser.Identity

        $userCounter ++

        $allTeamsPhoneUserDetails += $teamsPhoneUserDetails

    }

}

$unassignedRoutingRules = Get-CsTeamsUnassignedNumberTreatment

# Get all unassigned Calling Plan and Operator Connect phone numbers or all conference assigned numbers
foreach ($csOnlineNumber in $allCsOnlineNumbers | Where-Object { $_.PstnAssignmentStatus -eq "ConferenceAssigned" -or ($null -eq $_.AssignedPstnTargetId -and $_.NumberType -ne "DirectRouting") }) {

    $csOnlineNumberDetails = New-Object -TypeName psobject

    $phoneNumber = $csOnlineNumber.TelephoneNumber

    $phoneNumberPrettyIndex = $prettyNumbers.original.IndexOf($phoneNumber)

    if ($phoneNumberPrettyIndex -eq -1) {

        $phoneNumberPrettyIndex = "N/A"

    }

    else {

        $phoneNumberPretty = $prettyNumbers.formatted[$phoneNumberPrettyIndex]

    }

    if ($csOnlineNumber.PstnAssignmentStatus -eq "ConferenceAssigned") {

        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Title" -Value $phoneNumber
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $phoneNumberPretty
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value "N/A"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Status" -Value "Assigned"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Number_x0020_Type" -Value $csOnlineNumber.NumberType
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Operator" -Value $csOnlineNumber.PstnPartnerName
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "City" -Value $csOnlineNumber.City
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Country" -Value $csOnlineNumber.IsoCountryCode
    
    
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Name" -Value "$phoneNumber"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Principal_x0020_Name" -Value "$phoneNumber"

        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Account_x0020_Type" -Value "Conference Bridge"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "UserId" -Value "$phoneNumber"

    }

    else {

        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Title" -Value $phoneNumber
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $phoneNumberPretty
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value "N/A"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Status" -Value "Unassigned"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Number_x0020_Type" -Value $csOnlineNumber.NumberType
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Operator" -Value $csOnlineNumber.PstnPartnerName
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "City" -Value $csOnlineNumber.City
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Country" -Value $csOnlineNumber.IsoCountryCode
    
    
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Name" -Value "$phoneNumber"
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Principal_x0020_Name" -Value "$phoneNumber"
    
        if ($csOnlineNumber.Capability -contains "UserAssignment") {
    
            $accountType = "User Account"
    
        }
    
        elseif ($csOnlineNumber.Capability -contains "VoiceApplicationAssignment" -and $csOnlineNumber.Capability -notcontains "ConferenceAssignment") {
    
            $accountType = "Resource Account"
    
        }
    
        elseif ($csOnlineNumber.Capability -notcontains "VoiceApplicationAssignment" -and $csOnlineNumber.Capability -contains "ConferenceAssignment") {
    
            $accountType = "Conference Bridge"
    
        }
    
        else {
    
            $accountType = "Resource Account, Conference Bridge"
    
        }
    
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "Account_x0020_Type" -Value $accountType
        $csOnlineNumberDetails | Add-Member -MemberType NoteProperty -Name "UserId" -Value "Unassigned"   

    }

    $ruleMatches = @()

    foreach ($rule in $unassignedRoutingRules) {

        if ($phoneNumber -match $rule.Pattern) {

            $ruleMatches += $rule

        }

    }

    if ($ruleMatches) {

        if ($ruleMatches.Count -gt 1) {

            $ruleMatches = ($ruleMatches | Sort-Object -Property TreatmentPriority)[0]
    
        }

        $csOnlineNumberDetails.Status = "Unassigned (Routing Rule)"
        $csOnlineNumberDetails.User_x0020_Name = "Unassigned Routing Rule: $($ruleMatches.Identity)"

    }

    $allTeamsPhoneUserDetails += $csOnlineNumberDetails

}

# Get all unassigned Direct Routing Numbers
$directRoutingNumbers = $allDirectRoutingNumbers | Where-Object { $allTeamsPhoneUserDetails."Title" -notcontains $_.PhoneNumber }

foreach ($directRoutingNumber in $directRoutingNumbers) {

    $directRoutingNumberDetails = New-Object -TypeName psobject

    $phoneNumber = $directRoutingNumber.PhoneNumber

    $phoneNumberPrettyIndex = $prettyNumbers.original.IndexOf($phoneNumber)

    if ($phoneNumberPrettyIndex -eq -1) {

        $phoneNumberPrettyIndex = "N/A"

    }

    else {

        $phoneNumberPretty = $prettyNumbers.formatted[$phoneNumberPrettyIndex]

    }

    $country = . Get-CountryFromPrefix

    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Title" -Value $directRoutingNumber.PhoneNumber
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $phoneNumberPretty
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value "N/A"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Status" -Value "Unassigned"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Number_x0020_Type" -Value "DirectRouting"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Operator" -Value $directRoutingNumber.Operator
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "City" -Value "N/A"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Country" -Value $country

    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Name" -Value "Unassigned"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "User_x0020_Principal_x0020_Name" -Value "$phoneNumber"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "Account_x0020_Type" -Value "User Account, Resource Account"
    $directRoutingNumberDetails | Add-Member -MemberType NoteProperty -Name "UserId" -Value "Unassigned"

    $ruleMatches = @()

    foreach ($rule in $unassignedRoutingRules) {

        if ($phoneNumber -match $rule.Pattern) {

            $ruleMatches += $rule

        }

    }

    if ($ruleMatches) {

        if ($ruleMatches.Count -gt 1) {

            $ruleMatches = ($ruleMatches | Sort-Object -Property TreatmentPriority)[0]
    
        }

        $directRoutingNumberDetails.Status = "Unassigned (Routing Rule)"
        $directRoutingNumberDetails.User_x0020_Name = "Unassigned Routing Rule: $($ruleMatches.Identity)"

    }

    $allTeamsPhoneUserDetails += $directRoutingNumberDetails

}

if ($sharePointListItems) {

    foreach ($spoPhoneNumber in $sharePointListItems) {
    
        if ($spoPhoneNumber.Title -notin $allTeamsPhoneUserDetails.Title) {

            Write-Output "Entry $($spoPhoneNumber.Title) is no longer available. It will be removed from the list..."

            try {
                
                Invoke-RestMethod -Method Delete -Headers $Header -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($sharePointListId)/items/$($spoPhoneNumber.id)" -ErrorAction Stop

            }
            catch {

                Write-Output "Error while trying to update list item. Trying to get new token..."

                . Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                . Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

            }

        }

    }

}

# Update list

$updateCounter = 1

foreach ($teamsPhoneNumber in $allTeamsPhoneUserDetails) {

    if ($updateCounter % 100 -eq 0) {

        Write-Output "Working on $updateCounter/$($allTeamsPhoneUserDetails.Count)..."

    }

    if ($sharePointListItems.Title -contains $teamsPhoneNumber."Title") {

        $checkEntryIndex = $sharePointListItems.Title.IndexOf($teamsPhoneNumber.Title)
        $checkEntry = $sharePointListItems[$checkEntryIndex]

        $itemId = $checkEntry.id

        $checkEntryObject = New-Object -TypeName psobject

        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Title" -Value $checkEntry.Title
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "PhoneNumber" -Value $checkEntry.PhoneNumber
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Phone_x0020_Extension" -Value $checkEntry.Phone_x0020_Extension
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Status" -Value $checkEntry.Status
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Number_x0020_Type" -Value $checkEntry.Number_x0020_Type
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Operator" -Value $checkEntry.Operator
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "City" -Value $checkEntry.City
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Country" -Value $checkEntry.Country
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "User_x0020_Name" -Value $checkEntry.User_x0020_Name
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "User_x0020_Principal_x0020_Name" -Value $checkEntry.User_x0020_Principal_x0020_Name
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "Account_x0020_Type" -Value $checkEntry.Account_x0020_Type
        $checkEntryObject | Add-Member -MemberType NoteProperty -Name "UserId" -Value $checkEntry.UserId

        $compareObjects = ($checkEntryObject | Out-String) -eq ($teamsPhoneNumber | Out-String)

        if ($compareObjects) {

            # no differences

            # Write-Output "Entry $($teamsPhoneNumber.Title) is already up to date and won't be updated..."

        }

        else {

            if ($checkEntry.Status -match "Reserved" -and ($teamsPhoneNumber.Status -eq "Unassigned" -or $teamsPhoneNumber.Status -eq "Unassigned (Routing Rule)")) {

                if (!$checkEntry.PhoneNumber -or !$checkEntry.Operator) {

                    $newFormattedNumber = $teamsPhoneNumber.PhoneNumber
                    $newOperator = $teamsPhoneNumber.Operator
                    $teamsPhoneNumber = $checkEntryObject
                    $teamsPhoneNumber.PhoneNumber = $newFormattedNumber
                    $teamsPhoneNumber.Operator = $newOperator

                    Write-Output "Entry $($teamsPhoneNumber.Title) is reserved but has no pretty phone number or operator. Entry will be updated..."

                    $body = @"
{
"fields": 

"@
        
                    $body += ($teamsPhoneNumber | ConvertTo-Json)
                    $body += "`n}"
        
                    try {
                        
                        Invoke-RestMethod -Method Patch -Headers $header -ContentType "application/json; charset=UTF-8" -Body $body -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($sharePointListId)/items/$itemId" -ErrorAction Stop

                    }
                    catch {

                        Write-Output "Error while trying to update list item. Trying to get new token..."

                        . Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                        . Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                    }

                }

                elseif ($checkEntry.Status -match "Reserved" -and $teamsPhoneNumber.Status -eq "Unassigned (Routing Rule)") {

                    $teamsPhoneNumber.Status = "Reserved (Routing Rule)"

                    $body = @"
{
"fields": 

"@
                            
                    $body += ($teamsPhoneNumber | ConvertTo-Json)
                    $body += "`n}"
                            
                    try {
                        
                        Invoke-RestMethod -Method Patch -Headers $header -ContentType "application/json; charset=UTF-8" -Body $body -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($sharePointListId)/items/$itemId" -ErrorAction Stop

                    }
                    catch {

                        Write-Output "Error while trying to update list item. Trying to get new token..."

                        . Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                        . Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                    }

                }

                else {

                    Write-Output "Entry $($teamsPhoneNumber.Title) is reserved and will not be updated..."

                }

            }

            else {

                if ($checkEntry.Status -eq "Assignment Error" -and $teamsPhoneNumber.Status -ne "Assigned") {

                    $teamsPhoneNumber = $checkEntryObject

                    Write-Output "Entry $($teamsPhoneNumber.Title) is NOT up to date because it has assignment errors. Entry won't be updated..."

                }

                else {

                    Write-Output "Entry $($teamsPhoneNumber.Title) is NOT up to date. Entry will be updated..."

                }

                # patch

                $body = @"
{
"fields": 

"@
        
                $body += ($teamsPhoneNumber | ConvertTo-Json)
                $body += "`n}"
        
                try {
                    
                    Invoke-RestMethod -Method Patch -Headers $header -ContentType "application/json; charset=UTF-8" -Body $body -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($sharePointListId)/items/$itemId" -ErrorAction Stop

                }
                catch {

                    Write-Output "Error while trying to update list item. Trying to get new token..."

                    . Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                    . Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                }
            
            }

        }

    }

    else {

        # entry does not exist in list

        Write-Output "Entry $($teamsPhoneNumber.Title) is NEW..."

        $body = @"
{
"fields": 

"@

        $body += ($teamsPhoneNumber | ConvertTo-Json)
        $body += "`n}"

        # Only create list item if title is not empty
        if ($teamsPhoneNumber.Title) {

            try {

                Invoke-RestMethod -Method Post -Headers $header -ContentType "application/json; charset=UTF-8" -Body $body -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointSite.id)/lists/$($sharePointListId)/items" -ErrorAction Stop
            
            }
            catch {

                Write-Output "Error while trying to update list item. Trying to get new token..."

                . Connect-MsTeamsServicePrincipal -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

                . Connect-MgGraphHTTP -TenantId $TenantId -AppId $AppId -AppSecret $AppSecret

            }

        }
        
    }

    $updateCounter ++

    # Read-Host

}

if ($runbookBody.InvokedByFunction -eq $true) {

    $messageBody = @{
        MessageId         = "$($runbookBody.MessageId)"
        CompletedDateTime = (Get-Date -Format "o")
        StartDateTime     = (Get-Date -Date $($runbookBody.StartDateTime) -Format "o")
        TriggerPassword   = "ExamplePassword"
        TriggeredBy       = "$($runbookBody.TriggeredBy)"
        TriggeredByUpn    = "$($runbookBody.TriggeredByUpn)"
        JobAborted        = $false
    }

    $flowURI = "https://prod-226.westeurope.logic.azure.com:443/workflows/1a8d77007d6441a787d83ffe04be3417/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=YyoNrQRn2ZhSmoG1UvtG5oVjL_EtSSc35x-_ZcWV7ow"
    
    Invoke-RestMethod -Uri $flowURI -Method POST -ContentType "application/json; encoding='utf8'" -Body ($messageBody | ConvertTo-Json) -ErrorAction Stop

}