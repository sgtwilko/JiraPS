function Get-JiraUser
{
    <#
    .Synopsis
       Returns a user from Jira
    .DESCRIPTION
       This function returns information regarding a specified user from Jira.
    .EXAMPLE
       Get-JiraUser -UserName user1 -Credential $cred
       Returns information about the user user1
    .EXAMPLE
       Get-ADUser -filter "Name -like 'John*Smith'" | Select-Object -ExpandProperty samAccountName | Get-JiraUser -Credential $cred
       This example searches Active Directory for the username of John W. Smith, John H. Smith,
       and any other John Smiths, then obtains their JIRA user accounts.
    .INPUTS
       [String[]] Username
       [PSCredential] Credentials to use to connect to Jira
    .OUTPUTS
       [PSJira.User]
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByUserName')]
    param(
        # Username, name, or e-mail address of the user. Any of these should
        # return search results from Jira.
        [Parameter(ParameterSetName = 'ByUserName',
                   Mandatory = $true,
                   Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('User','Name')]
        [String[]] $UserName,

        [Parameter(ParameterSetName = 'ByInputObject',
                   Mandatory = $true,
                   Position = 0)]
        [Object[]] $InputObject,

        # Always run a search - don't attempt to return an exact match
        [Parameter()]
        [Alias('Search')]
        [Switch] $AlwaysSearch,

        # Include inactive users in the search
        [Parameter()]
        [Switch] $IncludeInactive,

        # Credentials to use to connect to Jira
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential] $Credential
    )

    begin
    {
        Write-Debug "[Get-JiraUser] Reading server from config file"
        $server = Get-JiraConfigServer -ConfigFile $ConfigFile -ErrorAction Stop

        Write-Debug "[Get-JiraUser] ParameterSetName=$($PSCmdlet.ParameterSetName)"

        Write-Debug "[Get-JiraUser] Building URI for REST call"
        $userSearchUrl = "$server/rest/api/latest/user/search?username={0}"
        if ($IncludeInactive)
        {
            $userSearchUrl = "$userSearchUrl&includeInactive=true"
        }

        $userGetUrl = "$server/rest/api/latest/user?username={0}&expand=groups"
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByUserName')
        {
            foreach ($u in $UserName)
            {
                if (-not $AlwaysSearch)
                {
                    Write-Debug "[Get-JiraUser] Checking for user with exact username [$u]"
                    $thisGetUrl = $userGetUrl -f $u
                    Write-Debug "[Get-JiraUser] Preparing for blastoff!"
                    # Invoke-JiraMethod normally writes error text if a user doesn't exist.
                    $userResult = Invoke-JiraMethod -Method Get -URI $thisGetUrl -Credential $Credential -ErrorAction SilentlyContinue
                } else {
                    Write-Debug "[Get-JiraUser] -AlwaysSearch was passed; skipping check for exact username"
                    $userResult = $null
                }

                if (-not $userResult)
                {
                    Write-Debug "[Get-JiraUser] No users were found with that exact name; invoking user search"
                    $thisSearchUrl = $userSearchUrl -f $u
                    Write-Debug "[Get-JiraUser] Preparing for blastoff!"
                    $rawResult = Invoke-JiraMethod -Method Get -URI $thisSearchUrl -Credential $Credential
                    if ($rawResult)
                    {
                        Write-Debug "[Get-JiraUser] Processing raw results from JIRA"
                        foreach ($r in $rawResult)
                        {
                            Write-Debug "[Get-JiraUser] Re-obtaining user information for user [$r]"
                            $url = '{0}&expand=groups' -f $r.self
                            Write-Debug "[Get-JiraUser] Preparing for blastoff!"
                            $thisUserResult = Invoke-JiraMethod -Method Get -URI $url -Credential $Credential

                            if ($thisUserResult)
                            {
                                Write-Debug "[Get-JiraUser] Converting result to PSJira.User object"
                                $thisUserObject = ConvertTo-JiraUser -InputObject $thisUserResult
                                Write-Output $thisUserObject
                            } else {
                                Write-Debug "[Get-JiraUser] User [$r] could not be found in JIRA."
                            }
                        }
                    }
                    else {
                        Write-Debug "[Get-JiraUser] No users were found with that search term"
                        Write-Verbose "No users were found in JIRA matching [$u]"
                    }
                }

                if ($userResult)
                {
                    Write-Debug "[Get-JiraUser] Found user with exact username; converting result to PSJira.User object"
                    $thisUserObject = ConvertTo-JiraUser -InputObject $userResult
                    Write-Output $thisUserObject
                }
            }
        } else {
            foreach ($i in $InputObject)
            {
                Write-Debug "[Get-JiraUser] Processing InputObject [$i]"
                if ((Get-Member -InputObject $i).TypeName -eq 'PSJira.User')
                {
                    Write-Debug "[Get-JiraUser] User parameter is a PSJira.User object"
                    $thisUserName = $i.Name
                } else {
                    $thisUserName = $i.ToString()
                    Write-Debug "[Get-JiraUser] Username is assumed to be [$thisUserName] via ToString()"
                }

                Write-Debug "[Get-JiraUser] Invoking myself with the UserName parameter set to search for user [$thisUserName]"
                $userObj = Get-JiraUser -UserName $thisUserName -Credential $Credential
                Write-Debug "[Get-JiraUser] Returned from invoking myself; outputting results"
                Write-Output $userObj
            }
        }
    }

    end
    {
        Write-Debug "[Get-JiraUser] Complete"
    }
}


