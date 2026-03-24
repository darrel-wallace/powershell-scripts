# Tests for Invoke-ExampleFunction
# Pester 3.4.0 syntax (ships with Windows Server 2019/2022)
#
# Run:
#   Invoke-Pester .\tests\<Category>\Invoke-ExampleFunction.Tests.ps1 -Verbose

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $here '..\..\scripts\<Category>\Invoke-ExampleFunction.ps1'

. $scriptPath

Describe 'Invoke-ExampleFunction' {

    Context 'When given valid input' {

        It 'Should return the expected result' {
            # Arrange
            $input = 'value'

            # Act
            $result = Invoke-ExampleFunction -ParamName $input

            # Assert
            $result | Should Be 'expected'
        }

        It 'Should not throw on valid input' {
            { Invoke-ExampleFunction -ParamName 'value' } | Should Not Throw
        }
    }

    Context 'When given invalid input' {

        It 'Should throw when ParamName is empty' {
            { Invoke-ExampleFunction -ParamName '' } | Should Throw
        }
    }
}
