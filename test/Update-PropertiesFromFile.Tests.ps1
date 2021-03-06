[System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ModuleRootPath = (Get-Location)
)

$moduleManifestName = 'azure.datafactory.tools.psd1'
$moduleManifestPath = Join-Path -Path $ModuleRootPath -ChildPath $moduleManifestName

Import-Module -Name $moduleManifestPath -Force -Verbose:$false

InModuleScope azure.datafactory.tools {
    #$testHelperPath = $PSScriptRoot | Split-Path -Parent | Join-Path -ChildPath 'TestHelper'
    #Import-Module -Name $testHelperPath -Force
    . ".\test\New-TempDirectory.ps1"

    # Variables for use in tests
    $script:SrcFolder = $env:ADF_ExampleCode
    $script:TmpFolder = (New-TemporaryDirectory).FullName
    $script:RootFolder = Join-Path -Path $script:TmpFolder -ChildPath (Split-Path -Path $script:SrcFolder -Leaf)
    $script:DeploymentFolder = Join-Path -Path $script:RootFolder -ChildPath "deployment"

    Copy-Item -Path "$SrcFolder" -Destination "$TmpFolder" -Filter "*.*" -Recurse:$true -Force 
    #Invoke-Expression "explorer.exe '$TmpFolder'"

    Describe 'Update-PropertiesFromFile' -Tag 'Unit','private' {
        It 'Should exist' {
            { Get-Command -Name Update-PropertiesFromFile -ErrorAction Stop } | Should -Not -Throw
        }

        Context 'When called without parameters' {
            It 'Should throw an error' {
                { Update-PropertiesFromFile } | Should -Throw 
            }
        }

        Context 'When called with parameters' {
            $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
            $script:option = New-AdfPublishOption
            It 'and adf param is empty should throw an error ' { {
                Update-PropertiesFromFile -stage "uat" -option $option -Force
                } | Should -Throw
            }
            It 'and stage param is empty should throw an error ' { {
                Update-PropertiesFromFile -adf $adf -option $option -Force
                } | Should -Throw
            }
            It 'and $adf.Location is empty should throw an error ' { {
                $script:adf.Location = ""
                Update-PropertiesFromFile -adf $adf -stage "uat" -option $option -Force
                } | Should -Throw
            }
        }

        Context 'When called with stage as short code but file does not exist' {
            $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
            $script:option = New-AdfPublishOption
            It 'Should throw an error' { {
                Update-PropertiesFromFile -adf $script:adf -stage "FakeStage" -option $option
                } | Should -Throw
            }
        }

        Context 'When called' {
            $script:now = Get-Date
            It 'Should return nothing' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                $result = Update-PropertiesFromFile -adf $script:adf -stage "UAT" -option $option
                $result | Should -Be $null
            }
            It 'Should not modify any files' {
                Start-Sleep -Milliseconds 100
                $modFiles = (Get-ChildItem -Path $RootFolder -Exclude "~*.*" -Filter "*.json" -Recurse:$true | Where-Object {$_.LastWriteTime -gt $now} )
                $modFiles | Should -Be $null
            }
            It 'Should contains properties replaced and correct types' {
                $t = Get-AdfObjectByName -adf $script:adf -name "TR_AlwaysDisabled" -type "Trigger"
                $t.Body.properties.typeProperties.recurrence.interval | Should -Be 2
                $t.Body.properties.typeProperties.recurrence.interval.GetType().Name | Should -Be 'Int32'
                $t.Body.properties.runtimeState | Should -Be 'Started'
                $t.Body.properties.runtimeState.GetType().Name | Should -Be 'String'
            }

        }

        
        Context 'When called and CSV has wrong format' {
            It 'Should throw' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "badformat" -option $option
                } | Should -Throw
            }
            It 'Should contains all properties unchanged' {
                $t = Get-AdfObjectByName -adf $script:adf -name "TR_AlwaysDisabled" -type "Trigger"
                $t.Body.properties.runtimeState | Should -Be 'Stopped'
                $t.Body.properties.typeProperties.recurrence.interval | Should -Be 1
            }
        }

        Context 'When called and CSV contains multiple sub-properties as value' {
            It 'Should complete' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "c002" -option $option
                } | Should -Not -Throw
            }
            It 'Should contains properties replaced and correct types' {
                $t = Get-AdfObjectByName -adf $script:adf -name "PL_Wait_Dynamic" -type "pipeline"
                $t.Body.properties.parameters.WaitInSec.type | Should -Be 'int32'
                $t.Body.properties.parameters.WaitInSec.defaultValue | Should -Be 22
            }
        }

        Context 'When called and CSV with commented rows' {
            It 'Should complete' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "commented" -option $option
                } | Should -Not -Throw
            }
            It 'Should not apply changes for commented rows' {
                $t = Get-AdfObjectByName -adf $script:adf -name "TR_AlwaysDisabled" -type "trigger"
                $t.Body.properties.runtimeState | Should -Be 'Started'
                $t.Body.properties.typeProperties.recurrence.interval | Should -Be 1
            }
        }

        Context 'When called and CSV contains incorrect path' {
            It 'Should throw' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "c004-wrongpath" -option $option
                } | Should -Throw -ExceptionType ([System.Data.DataException])
            }
        }

        Context 'When called and CSV has extra action (add/remove)' {
            It 'Should complete' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "c005-extra-action" -option $option
                } | Should -Not -Throw
            }
            It 'Should contains 1 updated property' {
                $script:ls = Get-AdfObjectByName -adf $script:adf -name "BlobSampleData" -type "linkedService"
                $script:ls.Body.properties.typeProperties.connectionString | Should -Be "DefaultEndpointsProtocol=https;AccountName=sqlplayer2019;EndpointSuffix=core.windows.net;"
            }
            It 'Should contains 1 new property' {
                $script:ls.Body.properties.typeProperties.accountKey | Should -Be "orefoifakerjgi40passwordrjegjorejgorjeogjoreg=="
            }
            It 'Should lost 1 property (removed)' {
                Get-Member -InputObject $script:ls.Body.properties.typeProperties -name "encryptedCredential" -Membertype "Properties" | Should -Be $null
            }
        }

        Context 'When called and CSV contains global parameters to be replaced' {
            It 'Should complete' {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    Update-PropertiesFromFile -adf $script:adf -stage "globalparam1" -option $option
                } | Should -Not -Throw
            }
            It 'Should contains gp values replaced' {
                $script:gp = Get-AdfObjectByName -adf $script:adf -name $script:adf.Factories[0].Name -type "factory"
                $script:gp.Body.properties.globalParameters.'GP-String'.value | Should -Be "This text has been replaced"
                $script:gp.Body.properties.globalParameters.'GP-Int'.value | Should -Be 2020
            }
        }

    } 

    Describe 'Update-PropertiesFromFile with JSON' -Tag 'Unit','private','jsonconfig' {
        
        $testCases =  @( @{ configFile = 'config-c100.csv' }, @{ configFile = 'config-c100.json' } )

        $Env:DatabricksClusterId = "0820-210125-test000"
        $Env:Region = "uks"
        $Env:ProjectName = "adft"
        $Env:Environment = "uat"

        Context 'When called and JSON has extra actions' {
            It 'Should complete and has properties updated, added and removed' -TestCases $testCases {
                $script:adf = Import-AdfFromFolder -FactoryName "xyz" -RootFolder "$RootFolder"
                $script:option = New-AdfPublishOption
                {
                    $configFilePath = Join-Path -Path $script:DeploymentFolder -ChildPath "$configFile"
                    Update-PropertiesFromFile -adf $script:adf -stage "$configFilePath" -option $option
                } | Should -Not -Throw

                $script:ls = Get-AdfObjectByName -adf $script:adf -name "LS_DataLakeStore" -type "linkedService"
                $script:ls.Body.properties.typeProperties.url | Should -Be "https://datalake$($Env:ProjectName)$($Env:Environment).dfs.core.windows.net/"
                $script:lsdbr = Get-AdfObjectByName -adf $script:adf -name "LS_AzureDatabricks" -type "linkedService"
                $script:lsdbr.Body.properties.typeProperties.existingClusterId | Should -Be "$($Env:DatabricksClusterId)"
                $script:lsdbr.Body.properties.typeProperties.domain | Should -Be "https://$($Env:Region).azuredatabricks.net"
                $script:ls = Get-AdfObjectByName -adf $script:adf -name "LS_AzureKeyVault" -type "linkedService"
                $script:ls.Body.properties.typeProperties.baseUrl | Should -Be "https://keyvault-$($Env:ProjectName)-$($Env:Environment).vault.azure.net/"

                Get-Member -InputObject $script:lsdbr.Body.properties.typeProperties -name "encryptedCredential" -Membertype "Properties" | Should -Be $null
            }
        }


    } 


}
