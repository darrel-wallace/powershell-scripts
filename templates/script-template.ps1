<#
.SYNOPSIS
    Brief one-line description of what this function does.

.DESCRIPTION
    Detailed description. Include what inputs are expected, what actions
    are taken, and what is returned or changed.

.PARAMETER ParamName
    Description of the parameter. Include type, expected values, and
    whether it is required or optional.

.EXAMPLE
    Invoke-ExampleFunction -ParamName 'value'

    Description of what this example demonstrates.

.NOTES
    Target:   Windows PowerShell 5.1
    Requires: No third-party modules
    Author:   Darrel Wallace
#>
function Invoke-ExampleFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = 'Description of param')]
        [ValidateNotNullOrEmpty()]
        [string]$ParamName
    )

    # Implementation here

}
