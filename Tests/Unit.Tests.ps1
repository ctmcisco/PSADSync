#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path | Split-Path -Parent | Split-Path -Parent)\PSADSync.psd1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psd1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

describe 'Module-level tests' {
	
	it 'should validate the module manifest' {
	
		{ Test-ModuleManifest -Path $ThisModule -ErrorAction Stop } | should not throw
	}

	it 'should pass all analyzer rules' {

		$excludedRules = @(
			'PSUseShouldProcessForStateChangingFunctions',
			'PSUseToExportFieldsInManifest',
			'PSAvoidInvokingEmptyMembers',
			'PSUsePSCredentialType',
			'PSAvoidUsingPlainTextForPassword'
			'PSAvoidUsingConvertToSecureStringWithPlainText'
		)

		Invoke-ScriptAnalyzer -Path $PSScriptRoot -ExcludeRule $excludedRules -Severity Error | Select-Object -ExpandProperty RuleName | should benullorempty
	}
}

InModuleScope $ThisModuleName {

	$script:AllAdUsers = 0..9 | ForEach-Object {
		$i = $_
		$adUser = @{}
		$props = @{
			'Name' = "nameval$i"
			'Enabled' = $true
			'SamAccountName' = "samval$i"
			'GivenName' = "givennameval$i"
			'Surname' = "surnameval$i"
			'DisplayName' = "displaynameval$i"
			'OtherProperty' = "otherval$i"
			'EmployeeId' = $i
			'Title' = "titleval$i"
		}
		$props.GetEnumerator() | ForEach-Object {
			if ($_.Key -eq 'Enabled') {
				if ($i % 2) {
					$adUser.($_.Key) = $false
				} else {
					$adUser.($_.Key) = $true
				}
			} else {
				$adUser.($_.Key) = "$($_.Value)$i"
			}
		}
		if ($i -eq 5) {
			$adUser.samAccountName = $null
		}
		if ($i -eq 6) { 
			$adUser.EmployeeId = $null
		}
		[pscustomobject]$adUser
	}

	$script:AllCsvUsers = 0..15 | ForEach-Object {
		$i = $_
		$output = @{ 
			AD_LOGON = "nameval$i"
			PERSON_NUM = "1$i" 
			ExcludeCol = 'dontexcludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'AD_LOGON' = $null
			$output.ExcludeCol = 'excludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'PERSON_NUM' = $null
		}
		[pscustomobject]$output 
	}

	describe 'Get-CompanyCsvUser' {
	
		$commandName = 'Get-CompanyCsvUser'
	
		#region Mocks
			$script:csvUsers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
					OtherAtrrib = 'x'
					ExcludeCol = 'excludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			)

			mock 'Import-Csv' {
				$script:csvUsers
			}

			mock 'Test-Path' {
				$true
			}

			$script:csvUsersNullConvert = $script:csvUsers | ForEach-Object { if (-not $_.'AD_LOGON') { $_.'AD_LOGON' = 'null' } $_ }
		#endregion
		
		$parameterSets = @(
			@{
				CsvFilePath = 'C:\users.csv'
				TestName = 'All users'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme' }
				TestName = 'Exclude 1 col'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme';ExcludeCol2 = 'excludeme' }
				TestName = 'Exclude 2 cols'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Exclude = $parameterSets.where({$_.ContainsKey('Exclude')})
			Exclude1Col = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 1)})
			Exclude2Cols = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 2)})
			NoExclusions = $parameterSets.where({ -not $_.ContainsKey('Exclude')})
		}

		context 'when at least one column is excluded' {

			mock 'Where-Object' {
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			} -ParameterFilter { $FilterScript.ToString() -notmatch '\*' }
		
			it 'should create the expected where filter: <TestName>' -TestCases $testCases.Exclude {
				param($CsvFilePath,$Exclude)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Where-Object'
					Times = $script:csvUsers.Count
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$PSBoundParameters.FilterScript.ToString() -like "(`$_.`'*' -ne '*')*" }
				}
				Assert-MockCalled @assMParams
			}
		
		}

		it 'when excluding no cols, should return all expected users: <TestName>' -TestCases $testCases.NoExclusions {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object $script:csvUsersNullConvert.'AD_LOGON' $result.'AD_LOGON').InputObject | should benullorempty
		}

		it 'when excluding 1 col, should return all expected users: <TestName>' -TestCases $testCases.Exclude1Col {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('foo2','notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	
		it 'when excluding 2 cols, should return all expected users: <TestName>' -TestCases $testCases.Exclude2Cols {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	}

	describe 'GetCsvColumnHeaders' {
		
		#region Mocks
			mock 'Get-Content' {
				@(
					'"Header1","Header2","Header3"'
					'"Value1","Value2","Value3"'
					'"Value4","Value5","Value6"'
				)
			}
		#endregion

		it 'should return expected headers' {
		
			$result = & GetCsvColumnHeaders -CsvFilePath 'foo.csv'
			Compare-Object $result @('Header1','Header2','Header3') | should benullorempty
		}
		
	}

	describe 'TestCsvHeaderExists' {
		
		$commandName = 'TestCsvHeaderExists'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'GetCsvColumnHeaders' {
				'nothinghere','nope'
			} -ParameterFilter { $CsvFilePath -eq 'C:\foofail.csv' }

			mock 'GetCsvColumnHeaders' {
				'Header','a','b','c','d','e'
			} -ParameterFilter { $CsvFilePath -eq 'C:\foopass.csv' }

			mock 'ParseScriptBlockHeaders' {
				'Header','a','b','c','d','e'
			}

		$testCases = @(
			@{
				Label = 'Single header / no scriptblocks'
				Parameters = @{
					CsvFilePath = 'C:\foofail.csv'
					Header = 'fail'
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 0
						}
					}
					Output = @{
						ReturnValue = $false
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Single header / 1 scriptblock'
				Parameters = @{
					CsvFilePath = 'C:\foofail.csv'
					Header = { if (-not $_.Header) { '2' } else { '3' } }
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 1
						}
					}
					Output = @{
						ReturnValue = $false
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Multiple headers / string/scriptblock'
				Parameters = @{
					CsvFilePath = 'C:\foopass.csv'
					Header = 
						'a',
						{ if (-not $_.Header) { 'b' } else { 'c' } },
						{ if (-not $_.Header) { 'd' } else { 'e' } }
				}
				Expected = @{
					Execution = @{
						ParseScriptBlockHeaders = @{
							RunTimes = 2
						}
					}
					Output = @{
						ReturnValue = $true
						ObjectCount = 1
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {
	
				$result = & $commandName @parameters

				it "should call ParseScriptBlockHeaders [$($expected.Execution.ParseScriptBlockHeaders.RunTimes)] times" {
					
					$assMParams = @{
						CommandName = 'ParseScriptBlockHeaders'
						Times = $expected.Execution.ParseScriptBlockHeaders.RunTimes
						Exactly = $true
					}
					Assert-MockCalled @assMParams
				}

				it "should return [$($expected.Output.ReturnValue)]" {
					$result | should be $expected.Output.ReturnValue
				}

				it "should return [$($expected.Output.ObjectCount)] object(s)" {
					@($result).Count | should be $expected.Output.ObjectCount
				}

				it 'should return the same object type in OutputType()' {
					$result | should beoftype $script:command.OutputType.Name
				}
			}
		}
	}

	describe 'Get-CompanyAdUser' {
		
		$commandName = 'Get-CompanyAdUser'
	
		#region Mocks
			mock 'Get-AdUser' {
				$script:allAdUsers
			}
		#endregion
	
		$testCases = @(
			@{
				Label = 'Single field match and field sync'
				Parameters = @{
					FieldMatchMap = @{ 'PERSON_NUM' = 'employeeId' }
					FieldSyncMap = @{ 'csvTitle' = 'title' }
				}
				Expected = @{
					Output = @{
						ObjectCount = 10
					}
				}
			}
			@{
				Label = 'Multiple field match and field sync'
				Parameters = @{
					FieldMatchMap = @{ 
						'PERSON_NUM' = 'employeeId'
						'csvId' = 'samAccountName' 
					}
					FieldSyncMap = @{ 
						'csvTitle' = 'title'
						'csvotherprop' = 'OtherProperty'
					}
				}
				Expected = @{
					Output = @{
						ObjectCount = 10
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters

				it "should return [$($expected.Output.ObjectCount)] objects" {
					$result.Count | should be $expected.Output.ObjectCount	
				}
	
			}
		}
	}

	describe 'ConvertToAdAttribute' {
		
		$commandName = 'ConvertToAdAttribute'
		$script:command = Get-Command -Name $commandName
	
		$testCases = @(
			@{
				Label = 'Multiple fields'
				Parameters = @{
					CsvUser = ([pscustomobject]@{ 
						'csvcity' = 'x'
						'csvtitle' = 'y'
					})
					FieldMap = @{
						'csvcity' = 'adcity'
						'csvtitle' = 'adtitle'
					}
				}
				Expected = @{
					Output = @{
						Returns = @{ 
							'adcity' = 'x'
							'adtitle' = 'y'
						}
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Multiple fields / one match'
				Parameters = @{
					CsvUser = ([pscustomobject]@{ 
						'csvcity' = 'x'
						'csvtitle' = 'y'
					})
					FieldMap = @{
						'csvcity' = 'adcity'
						'csvtitletypo' = 'adtitle'
					}
				}
				Expected = @{
					Output = @{
						Returns = @{ 
							'adcity' = 'x'
						}
						ObjectCount = 1
					}

				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$result = & $commandName @parameters
	
				it "should return [$($expected.Output.ObjectCount)] object(s)" {
					@($result).Count | should be $expected.Output.ObjectCount
				}

				it 'should return the same object type in OutputType()' {
					$result | should beoftype $script:command.OutputType.Name
				}

				it 'should return the expected hashtable' {
					-not (Compare-Object ([array]$result.Keys) $expected.Output.Returns.Keys) -and
					-not (Compare-Object ([array]$result.Values) $expected.Output.Returns.Values)
				}
			}
		}
	}

	describe 'FindUserMatch' {
	
		$commandName = 'FindUserMatch'
		
		#region Mocks
			mock 'Write-Warning'

			$script:csvUserMatchOnOneIdentifer = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:csvUserMatchOnAllIdentifers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
				}
			)

			$script:OneblankCsvUserIdentifier = @(
				[pscustomobject]@{
					PERSON_NUM = $null
					AD_LOGON = 'foo'
				}
			)

			$script:AllblankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = $null
				}
			)
			
			$script:noBlankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
				}
			)

			$script:firstLastMatchCsvUserId = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
					FIRST_NAME = 'adfirstname1'
					LAST_NAME = 'adlastname1'
				}
			)

			$script:firstLastNickMatchCsvUserId = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
					FIRST_NAME = $null
					LAST_NAME = 'adlastnamex'
					NICK_NAME = 'adfirstnamex'
				}
			)

			$script:firstLastNickMatchCsvUserId2 = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
					FIRST_NAME = 'adfirstnamex'
					LAST_NAME = 'adlastnamex'
					NICK_NAME = $null
				}
			)

			$script:csvUserNoMatch = @(
				[pscustomobject]@{
					AD_LOGON = 'NotInAd'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:AdUsers = @(
				[pscustomobject]@{
					samAccountName = 'foo'
					EmployeeId = 123
					givenName = 'adfirstname1'
					surName = 'adlastname1'
				}
				[pscustomobject]@{
					samAccountName = 'foo3'
					EmployeeId = 1234
					givenName = 'adfirstname1'
					surName = 'adlastname5'
				}
				[pscustomobject]@{
					samAccountName = 'foo2'
					EmployeeId = 111
					givenName = 'adfirstname2'
					surName = 'adlastname2'
				}
				[pscustomobject]@{
					samAccountName = 'foo9'
					EmployeeId = 999
					givenName = 'adfirstnamex'
					surName = 'adlastnamex'
				}
				[pscustomobject]@{
					samAccountName = 'NotinCSV'
					EmployeeId = 12345
					givenName = 'adfirstname3'
					surName = 'adlastname3'
				}
			)
		#endregion
		
		$parameterSets = @(
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnOneIdentifer
				FieldMatchMap = @{ 'AD_LOGON' = 'samAccountName' }
				TestName = 'Match on 1 ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnAllIdentifers
				FieldMatchMap = @{ 'PERSON_NUM' = 'EmployeeId' }
				TestName = 'Match on all IDs'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserNoMatch
				FieldMatchMap = @{ 'PERSON_NUM' = 'EmployeeId' }
				TestName = 'No Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:OneblankCsvUserIdentifier
				FieldMatchMap = [ordered]@{ 
					'PERSON_NUM' = 'EmployeeId'
					'AD_LOGON' = 'samAccountName'
				}
				TestName = 'One Blank ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:AllblankCsvUserIdentifier
				FieldMatchMap = @{ 
					'PERSON_NUM' = 'EmployeeId'
					'AD_LOGON' = 'samAccountName'
				}
				TestName = 'All Blank IDs'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:firstLastMatchCsvUserId
				FieldMatchMap = @{ @( 'FIRST_NAME','LAST_NAME') = @('givenName','surName') }
				TestName = 'Multi-string'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:firstLastNickMatchCsvUserId
				FieldMatchMap = @{ @({ if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME'} },'LAST_NAME') = @('givenName','surName') }
				TestName = 'Multi-string conditional'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			MatchOnOneId = $parameterSets.where({$_.TestName -eq 'Match on 1 ID'})
			MatchOnAllIds = $parameterSets.where({$_.TestName -eq 'Match on all IDs'})
			MatchOnFirstNameLastName = $parameterSets.where({$_.TestName -eq 'Multi-string'})
			MatchOnFirstNameLastNameConditional = $parameterSets.where({$_.TestName -eq 'Multi-string conditional'})
			NoMatch = $parameterSets.where({$_.TestName -eq 'No Match'})
			OneBlankId = $parameterSets.where({ $_.CsvUser.AD_LOGON -and -not $_.CsvUser.PERSON_NUM })
			AllBlankIds = $parameterSets.where({ -not $_.CsvUser.AD_LOGON -and (-not $_.CsvUser.PERSON_NUM) })
		}

		context 'When no matches could be found' {
			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.NoMatch {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				& $commandName @PSBoundParameters | should benullorempty
			}
		}

		context 'When one match can be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CSVAttemptedMatchIds | should be 'AD_LOGON'
				$result.ADAttemptedMatchIds | should be 'samAccountName'

			}
		}

		context 'when multiple matches on a single attribute are found' {
			

			it 'should throw an exception: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)

				{ & $commandName @parameters } | should throw 
			}
		
		}

		context 'When multiple matches on different attributes are be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CSVAttemptedMatchIds | should be 'PERSON_NUM'
				$result.ADAttemptedMatchIds | should be 'employeeid'

			}
		}

		context 'when a blank identifier is queried before finding a match' {

			it 'should return the expected object properties: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				$result.MatchedAdUser.samAccountName | should be 'foo'
				$result.CSVAttemptedMatchIds | should be 'PERSON_NUM,AD_LOGON'
				$result.ADAttemptedMatchIds | should be 'EmployeeId,samAccountName'
			}

		}

		context 'when all identifiers are valid' {
		
			it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				@($result.MatchedAdUser).foreach({
					$_.PSObject.Properties.Name -contains 'EmployeeId' | should be $true
				})
				$result.CSVAttemptedMatchIds | should be 'PERSON_NUM'
				$result.ADAttemptedMatchIds | should be 'employeeId'
			}
		
		}

		context 'when matching on multi-string' {

			it 'should return a single object: <TestName>' -TestCases $testCases.MatchOnFirstNameLastName {
				param($AdUsers,$CsvUser,$FieldMatchMap)

				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1

			}

			it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnFirstNameLastName {
				param($AdUsers,$CsvUser,$FieldMatchMap)
			
				$result = & $commandName @PSBoundParameters
				$result.MatchedAdUser.EmployeeId | should be 123
				$result.MatchedAdUser.givenName | should be 'adfirstname1'
				$result.MatchedAdUser.surName | should be 'adlastname1'
				$result.CSVAttemptedMatchIds | should be 'FIRST_NAME,LAST_NAME'
				$result.ADAttemptedMatchIds | should be 'givenName,surName'
			}

		}

		context 'when matching on a conditional multi-string' {

			it 'should return a single object: <TestName>' -TestCases $testCases.MatchOnFirstNameLastNameConditional {
				param($AdUsers,$CsvUser,$FieldMatchMap)

				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1

			}

			context 'when a preferred CSV field is null' {

				it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnFirstNameLastNameConditional {
					param($AdUsers,$FieldMatchMap)
				
					$result = & $commandName @PSBoundParameters -CsvUser $script:firstLastNickMatchCsvUserId2
					$result.MatchedAdUser.EmployeeId | should be 999
					$result.MatchedAdUser.givenName | should be 'adfirstnamex'
					$result.MatchedAdUser.surName | should be 'adlastnamex'
					$result.CSVAttemptedMatchIds | should be 'FIRST_NAME,LAST_NAME'
					$result.ADAttemptedMatchIds | should be 'givenName,surName'
				}
				
			}
			
			context 'when a preferred CSV field is not null' {

				it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnFirstNameLastNameConditional {
					param($AdUsers,$FieldMatchMap)
				
					$result = & $commandName @PSBoundParameters -CsvUser $script:firstLastNickMatchCsvUserId
					$result.MatchedAdUser.EmployeeId | should be 999
					$result.MatchedAdUser.givenName | should be 'adfirstnamex'
					$result.MatchedAdUser.surName | should be 'adlastnamex'
					$result.CSVAttemptedMatchIds | should be 'NICK_NAME,LAST_NAME'
					$result.ADAttemptedMatchIds | should be 'givenName,surName'
				}
				$script:firstLastNickMatchCsvUserId
			}

			

		}
	}

	describe 'NewUsername' {
		
		$commandName = 'NewUsername'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			
		#endregion
	
		$testCases = @(
			@{
				Label = 'Valid FirstInitialLastName'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
					})
					Pattern = 'FirstInitialLastName'
					FieldMap = @{
						FirstName = 'First'
						LastName = 'Last'
					}
				}
				Expected = @{
					Output = @{
						Value = 'tuser'
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Valid FirstNameLastName'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
					})
					Pattern = 'FirstNameLastName'
					FieldMap = @{
						FirstName = 'First'
						LastName = 'Last'
					}
				}
				Expected = @{
					Output = @{
						Value = 'testuser'
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Valid FirstNameDotLastName'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
					})
					Pattern = 'FirstNameDotLastName'
					FieldMap = @{
						FirstName = 'First'
						LastName = 'Last'
					}
				}
				Expected = @{
					Output = @{
						Value = 'test.user'
						ObjectCount = 1
					}
				}
			}
			@{
				Label = 'Invalid: pattern'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
					})
					Pattern = 'invalidpattern'
					FieldMap = @{
						FirstName = 'First'
						LastName = 'Last'
					}
				}
				Expected = @{
					ExceptionMessage = 'Unrecognized UserNamePattern'
				}
			}
			@{
				Label = 'Invalid: CsvUser does not contain all user attribs'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
					})
					Pattern = 'invalidpattern'
					FieldMap = @{
						FirstName = 'First'
					}
				}
				Expected = @{
					ExceptionMessage = 'One or more values in FieldMap parameter are missing'
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {
				
				if ($expected.ContainsKey('ExceptionMessage')) {

					it 'should throw an exception' {
					
						{ & $commandName @parameters } | should throw $expected.ExceptionMessage
					}
				} else {

					$result = & $commandName @parameters

					it "should return [$($expected.Output.ObjectCount)] object(s)" {
						@($result).Count | should be $expected.Output.ObjectCount
					}

					it 'should return the same object type in OutputType()' {
						$result | should beoftype $script:command.OutputType.Name
					}

					it "should return [$($expected.Output.Value)]" {
						$result | should be $expected.Output.Value
					}
				}
			}
		}
	}

	describe 'New-CompanyAdUser' {
		
		$commandName = 'New-CompanyAdUser'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'Set-AdAccountPassword'

			mock 'NewUserName' {
				'tuser'
			} -ParameterFilter { $Pattern -eq 'FirstInitialLastName' }

			mock 'NewUserName' {
				'testuser'
			} -ParameterFilter { $Pattern -eq 'FirstNameLastName' }

			mock 'NewUserName' {
				'test.user'
			} -ParameterFilter { $Pattern -eq 'FirstNameDotLastName' }

			mock 'NewRandomPassword' {
				ConvertTo-SecureString -String 'randompwhere' -AsPlainText -Force
			}

			mock 'Get-AdUser'

			mock 'New-AdUser' {
				[pscustomobject]@{
					DistinguishedName = 'newuserdn'
				}
			}
		#endregion
	
		$testCases = @(
			@{
				Label = 'Random password'
				Parameters = @{
					CsvUser = ([pscustomobject]@{
						First = 'Test'
						Last = 'User'
						Title = 'testtitle'
						'PERSON_NUM' = '1234'
					})
					UsernamePattern = 'FirstInitialLastName'
					RandomPassword = $true
					UserMatchMap = @{
						FirstName = 'First'
						LastName = 'Last'
					}
					FieldSyncMap = @{
						title = 'Title'
					}
					FieldMatchMap = @{ 'PERSON_NUM' = 'employeeId' }
					Confirm = $false
				}
				Expected = @{
					Execution = @{
						'Set-AdAccountPassword' = @{
							Parameters = @{
								Identity = 'newuserdn'
							}
							RunTimes = 1
						}
						'New-AdUser' = @{
							Parameters = @{
								Name = 'tuser'
								GivenName = 'test'
								Surname = 'user'
								OtherAttributes = @{ Title = 'testtitle'; employeeId = '1234' }
							}
							RunTimes = 1
						}
						'Get-AdUser' = @{
							Parameters = @{
								Filter = "samAccountName -eq 'tuser'"
							}
							RunTimes = 1
						}
					}
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				context 'when the user to be created already exists' {

					mock 'Get-AdUser' {
						[pscustomobject]@{}
					}

					it 'should throw an exception' {
					
						{ & $commandName @parameters } | should throw 'already exists'
					}
				
				}

				context 'Shared Tests' {

					$result = & $commandName @parameters

					it 'should pass the expected parameters to Get-AdUser' {
					
						$thisFunc = $expected.Execution.'Get-AdUser'
					
						$assMParams = @{
							CommandName = 'Get-AdUser'
							Times = $thisFunc.RunTimes
							Exactly = $true
							ExclusiveFilter = {
								$PSBoundParameters.Filter -eq $thisFunc.Parameters.Filter
							}
						}
						Assert-MockCalled @assMParams
					}

					it 'should pass the expected parameters to New-AdUser' {
					
						$thisFunc = $expected.Execution.'New-AdUser'
					
						$assMParams = @{
							CommandName = 'New-AdUser'
							Times = $thisFunc.RunTimes
							Exactly = $true
							ExclusiveFilter = {
								$PSBoundParameters.Name -eq $thisFunc.Parameters.Name -and
								$PSBoundParameters.GivenName -eq $thisFunc.Parameters.GivenName -and
								$PSBoundParameters.Surname -eq $thisFunc.Parameters.SurName -and
								$PSBoundParameters.OtherAttributes.Title -eq $thisFunc.Parameters.OtherAttributes.Title -and
								$PSBoundParameters.OtherAttributes.EmployeeId -eq $thisFunc.Parameters.OtherAttributes.EmployeeId
							}
						}
						Assert-MockCalled @assMParams
					}

					it 'should pass the expected parameters to Set-AdAccountPassword' -Skip {
					
						$thisFunc = $expected.Execution.'Set-AdAccountPassword'
					
						$assMParams = @{
							CommandName = 'Set-AdAccountPassword'
							Times = $thisFunc.RunTimes
							Exactly = $true
							ParameterFilter = {
								Write-Host ($PSBoundParameters.Identity | Out-String)
								Write-Host ($thisFunc.Parameters.Identity)
								$PSBoundParameters.Identity.samAccountName -eq $thisFunc.Parameters.Identity
							}
						}
						Assert-MockCalled @assMParams
					}

					it "should return nothing" {
						$result | should benullorempty
					}

				}
			}
		}
	}
	
	describe 'TestFieldMapIsValid' {
		
		$commandName = 'TestFieldMapIsValid'
		$script:command = Get-Command -Name $commandName
	
		#region Mocks
			mock 'TestCsvHeaderExists' {
				$true
			}

			mock 'Write-Warning'
		#endregion
	
		$testCases = @(
			@{
				Label = 'FieldSyncMap invalid'
				Parameters = @{
					FieldSyncMap = @{ 'string' = { $null } }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $false
				}
			}
			@{
				Label = 'FieldSyncMap valid'
				Parameters = @{
					FieldSyncMap = @{ { $null } = 'string' }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $true
				}
			}
			@{
				Label = 'FieldMatchMap invalid'
				Parameters = @{
					FieldMatchMap = @{ 'string' = { $null } }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $false
				}
			}
			@{
				Label = 'FieldMatchMap valid'
				Parameters = @{
					FieldMatchMap = @{ { $null } = 'string' }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $true
				}
			}
			@{
				Label = 'FieldValueMap invalid'
				Parameters = @{
					FieldValueMap = @{ { $null } = 'string' }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $false
				}
			}
			@{
				Label = 'FieldValueMap valid'
				Parameters = @{
					FieldValueMap = @{ 'string' = { $null } }
					CsvFilePath = 'x'
				}
				Expected = @{
					ShouldReturn = $true
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {
	
				$result = & $commandName @parameters

				it "should return [$($expected.ShouldReturn)]" {
					$result | should be $expected.ShouldReturn
				}

			}
		}
	}

	describe 'FindAttributeMismatch' {
	
		$commandName = 'FindAttributeMismatch'
		
		#region Mocks
			mock 'Write-Verbose'

			$script:csvUserMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 123
				OtherAttrib = 'x'
			}

			$script:csvUserNoMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 1111
				OtherAttrib = 'y'
			}

			$script:AdUserMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'otherattribmap' -Force -Value $null -PassThru

			$script:AdUserNoMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 1111
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'otherattribmap' -Force -Value 'y' -PassThru

			mock 'Get-Member' {
				[pscustomobject]@{
					Name = 'samAccountName'
				}
				[pscustomobject]@{
					Name = 'EmployeeId'
				}
				[pscustomobject]@{
					Name = 'otherattribmap'
				}
			}
		#endregion
		
		$testCases = @(
			@{
				Label = 'Mismatch'
				Parameters = @{
					AdUser = $script:AdUserMisMatch
					CsvUser = $script:csvUserMisMatch
					FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				}
			}
			@{
				Label = 'No mismatch'
				Parameters = @{
					AdUser = $script:AdUserNoMisMatch
					CsvUser = $script:csvUserNoMisMatch
					FieldSyncMap = @{ 'OtherAttrib' = 'otherattribmap' }
				}
			}
		)

		foreach ($testCase in $testCases) {

			$parameters = $testCase.Parameters

			context $testCase.Label {

				if ($testCase.Label -eq 'No mismatch') {
					context 'when no attribute mismatch is found' {

						$result = & $commandName @parameters

						it 'should return nothing' {
							$result | should benullorempty
						}

					}
				}

				if ($testCase.Label -eq 'Mismatch') {
					context 'when an attribute mismatch is found' {

						$result = & $commandName @parameters
						
						it 'should return the expected objects' {
							@($result).Count | should be 1
							$result | should beoftype 'hashtable'
							$result.ActiveDirectoryAttribute.otherattribmap | should benullorempty
							$result.CSVField.OtherAttrib | should be 'x'
							$result.ADShouldBe.otherattribmap | should be 'x'
						}
					}
				}
			}
		}
	}

	describe 'ConvertToAdUser' {
		
		$commandName = 'ConvertToAdUser'

		mock 'Get-AdUser'
	
		$testCases = @(
			@{
				Label = 'username'
				Parameters = @{
					String = 'jdoe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(samAccountName=jdoe))'
				}
			}
			@{
				Label = 'FirstName LastName'
				Parameters = @{
					String = 'John Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'FirstName      LastName'
				Parameters = @{
					String = 'John      Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'FirstName LastName'
				Parameters = @{
					String = 'John Doe'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'LastName, FirstName'
				Parameters = @{
					String = 'Doe, John'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'LastName,FirstName'
				Parameters = @{
					String = 'Doe,John'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(&(givenName=John)(sn=Doe)))'
				}
			}
			@{
				Label = 'DistinguishedName'
				Parameters = @{
					String = 'CN=jdoe,DC=domain,DC=local'
				}
				Expected = @{
					LdapFilter = '(&(objectCategory=person)(objectClass=user)(distinguishedName=CN=jdoe,DC=domain,DC=local))'
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {

				$null = & $commandName @parameters

				it 'should query for the expected user' {
					$assMParams = @{
						CommandName = 'Get-AdUser'
						Times = 1
						Exactly = $true
						ExclusiveFilter = { 
							$PSBoundParameters.LdapFilter -eq $expected.LdapFilter
						}
					}
					Assert-MockCalled @assMParams
				}
	
			}
		}
	}

	describe 'TestIsValidAdAttribute' {
		
		$commandName = 'TestIsValidAdAttribute'
	
		$testCases = @(
			@{
				Label = 'Mandatory'
				Parameters = @{
					Name = 'attribname'
				}
			}
		)
	
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
	
			context $testCase.Label {
	
				context 'when the attribute exists' {

					mock 'Get-AvailableAdUserAttribute' {
						[pscustomobject]@{
							'ValidName' = 'attribName'
						}
					}
	
					$result = & $commandName @parameters
	
					it 'should return $true' {
						$result | should be $true
					}
				}
	
				context 'when the attribute does not exist' {

					mock 'Get-AvailableAdUserAttribute' {
						@('notinhere')
					}
	
					$result = & $commandName @parameters
	
					it 'should return $false' {
						$result | should be $false
					}
				}
			}
		}
	}

	describe 'ConvertToSchemaAttributeType' {
		
		$commandName = 'ConvertToSchemaAttributeType'
		$script:command = Get-Command -Name $commandName
	
		$testCases = @(
			@{
				Label = 'AD accountExpires value'
				Parameters = @{
					AttributeName = 'accountExpires'
					AttributeValue = '131907060000000000'
				}
				Expected = @{
					Output = @{
						ObjectCount = 1
						ObjectType = 'datetime'
						Value = @('12/30/2018 00:00:00','12/30/2018 05:00:00')
					}
				}
			}
			@{
				Label = 'CSV accountExpires string'
				Parameters = @{
					AttributeName = 'accountExpires'
					AttributeValue = '12/30/18'
				}
				Expected = @{
					Output = @{
						ObjectCount = 1
						ObjectType = 'datetime'
						Value = @('12/30/2018 00:00:00','12/30/2018 05:00:00')
					}
				}
			}
			@{
				Label = 'Unrecognized string'
				Parameters = @{
					AttributeName = 'x'
					AttributeValue = '12/30/18'
				}
				Expected = @{
					Output = @{
						ObjectCount = 1
						ObjectType = 'string'
						Value = '12/30/18'
					}
				}
			}
		)
		foreach ($testCase in $testCases) {
	
			$parameters = $testCase.Parameters
			$expected = $testCase.Expected
	
			context $testCase.Label {
	
				$result = & $commandName @parameters

				it "should return [$($expected.Output.ObjectCount)] object(s)" {
					@($result).Count | should be $expected.Output.ObjectCount
				}

				it "should return an object of type [$($expected.Output.ObjectType)]" {
					$result | should beoftype $expected.Output.ObjectType
				}

				it "should return [$($expected.Output.Value)]" {
					$result | should bein $expected.Output.Value
				}
			}
		}
	}


	describe 'SetAduser' {
	
		$commandName = 'SetAduser'
		
		mock 'Set-AdUser'

		mock 'ConvertToSchemaAttributeType' {
			'1/1/01'
		} -ParameterFilter { $AttributeName -eq 'accountExpires' }

		mock 'ConvertToSchemaAttributeType' {
			'empidhere'
		} -ParameterFilter { $AttributeName -eq 'empidhere' }

		mock 'ConvertToSchemaAttributeType' {
			'displaynamehere'
		} -ParameterFilter { $AttributeName -eq 'displaynamehere' }

		mock 'ConvertToSchemaAttributeType' {
			'1/1/01'
		} -ParameterFilter { $AttributeName -eq '1/1/01' }
	
		$parameterSets = @(
			@{
				Identity = @{ samAccountName = 'samnamehere'}
				ActiveDirectoryAttributes = @{ employeeId = 'empidhere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				ActiveDirectoryAttributes = @{ displayName = 'displaynamehere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				ActiveDirectoryAttributes = @{ accountExpires = '1/1/01' }
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'returns nothing' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			& $commandName @PSBoundParameters -Confirm:$false | should benullorempty
		}

		it 'should set the expected attribute' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			## Need to account for the addition of ConvertToSchemaValue
		
			& $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'Set-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Replace.Keys -match 'displayName|employeeId|accountexpires' -and
					$PSBoundParameters.Replace.Values -match 'displayNameHere|empIdHere|1/1/01'
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'should set the expected identity' -TestCases $testCases.All {
			param($Identity,$ActiveDirectoryAttributes)

			& $commandName @PSBoundParameters -Confirm:$false
		
			$assMParams = @{
				CommandName = 'Set-AdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Identity -eq $Identity
				}
			}
			Assert-MockCalled @assMParams
		}
	
	}

	describe 'SyncCompanyUser' {
	
		$commandName = 'SyncCompanyUser'

		$script:csvUser = [pscustomobject]@{
			AD_LOGON = 'foo'
			PERSON_NUM = 123
			OtherAtrrib = 'x'
		}
	
		#region Mocks
			mock 'SetAdUser'
		#endregion
	
		$testCases = @(
			@{
				Label = 'SamAccountName Identifier'
				Parameters = @{
					Identity = 'foo'
					CsvUser = $script:csvUser
					ActiveDirectoryAttributes = @{ 
						'atttribtosync1' = 'attribtosyncval1'
					}
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = 'foo'
								ActiveDirectoryAttributes = @{ 'atttribtosync1' = 'attribtosyncval1' }
							}
						)
					}
				)
			}
			@{
				Label = 'EmployeeId Identifier, 2 Attributes hashtables'
				Parameters = @{
					Identity = 'bar'
					CsvUser = $script:csvUser
					ActiveDirectoryAttributes = @{ 
						'atttribtosync1' = 'attribtosyncval1'
						'atttribtosync2' = 'attribtosyncval2'
					}
				}
				Expect = @(
					@{
						Type = 'Function parameters'
						Name = 'SetAdUser'
						Parameters = @(
							@{
								Identity = 'bar'
								ActiveDirectoryAttributes = @(@{ 'atttribtosync1' = 'attribtosyncval1' },@{ 'atttribtosync2' = 'attribtosyncval2' })
							}
						)
					}
				)
			}
		)
	
		foreach ($testCase in $testCases) {
	
			context $testcase.Label {
	
				$expect = $testcase.Expect
				$funcParams = $testCase.Parameters
	
				$result = & $commandName @funcParams
	
				it 'should return nothing' {
					$result | should benullorempty
				}
	
				it 'should change only those attributes in the Attributes parameter' {

					$expectedParams = $expect.where({ $_.Name -eq 'SetAdUser'})

					$assMParams = @{
						CommandName = 'SetAdUser'
						Times = @($funcParams.ActiveDirectoryAttributes).Count
						Exactly = $true
						ParameterFilter = {
							$expectedkeys = $expectedParams.Parameters.ActiveDirectoryAttributes | ForEach-Object { $_.Keys }
							$expectedVals = $expectedParams.Parameters.ActiveDirectoryAttributes | ForEach-Object { $_.Values }
							
							$actualKeys = $PSBoundParameters.ActiveDirectoryAttributes  | ForEach-Object { $_.Keys }
							$actualValues = $PSBoundParameters.ActiveDirectoryAttributes  | ForEach-Object { $_.Values }
							-not (Compare-Object $expectedkeys $actualKeys) -and -not (Compare-Object $expectedVals $actualValues)
						}
					}
					Assert-MockCalled @assMParams
				}

				it 'should change attributes on the expected user account' {

					$expectedParams = $expect.where({ $_.Name -eq 'SetAdUser'})

					$assMParams = @{
						CommandName = 'SetAdUser'
						Times = @($funcParams.Attributes).Count
						Exactly = $true
						ParameterFilter = {
							foreach ($i in $expectedParams.Parameters) {
								$PSBoundParameters.Identity -in $i.Identity
							}
						}
					}
					Assert-MockCalled @assMParams
				}
			}
		}
	}
		
	describe 'WriteLog' {
	
		$commandName = 'WriteLog'
		

		mock 'Get-Date' {
			'time'
		}

		mock 'Export-Csv'
	
		$parameterSets = @(
			@{
				FilePath = 'C:\log.csv'
				CSVIdentifierValue = 'username'
				CSVIdentifierField = 'employeeid'
				Attributes = @{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'PERSON_NUM'
					CSVAttributeValue = 123
				}
				TestName = 'Standard'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should export a CSV to the expected path: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $PSBoundParameters.Path -eq $FilePath }
			}
			Assert-MockCalled @assMParams
		}

		it 'should appends to the CSV: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $Append }
			}
			Assert-MockCalled @assMParams
		}

		it 'should export as CSV with the expected values: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$InputObject.Time -eq 'time' -and
					$InputObject.CSVIdentifierValue -eq $CSVIdentifierValue -and
					$InputObject.CSVIdentifierField -eq $CSVIdentifierField -and
					$InputObject.ADAttributeName -eq 'EmployeeId' -and
					$InputObject.ADAttributeValue -eq $null -and
					$InputObject.CSVAttributeName -eq 'PERSON_NUM' -and
					$InputObject.CSVAttributeValue -eq 123
				}
			}
			Assert-MockCalled @assMParams
		}
	}

	describe 'Invoke-AdSync' {
	
		$commandName = 'Invoke-AdSync'
	
		#region Mocks
			$script:testAdUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
				$amParams = @{
					MemberType = 'NoteProperty'
					Force = $true
				}
				$props = @{
					'Name' = 'nameval'
					'Enabled' = $true
					'SamAccountName' = 'samval'
					'GivenName' = 'givennameval'
					'Surname' = 'surnameval'
					'ADDisplayName' = 'displaynameval'
					'OtherProperty' = 'otherval'
					'EmployeeId' = 1
					'ADTitle' = 'titleval'
				}
				$props.GetEnumerator() | ForEach-Object {
					$script:testAdUser | Add-Member @amParams -Name $_.Key -Value $_.Value
				}
				$script:testAdUser

			mock 'WriteLog'
			
			mock 'Test-Path' {
				$true
			}

			mock 'SyncCompanyUser'

			mock 'Write-Warning'

			mock 'TestCsvHeaderExists' {
				$true
			}

			mock 'Get-CompanyAdUser' {
				$script:testAdUser
			}

			mock 'Get-CompanyCsvUser' {
				[pscustomobject]@{ 
					AD_LOGON = "nameval"
					PERSON_NUM = "1"
					SUPERVISOR_ID = '2'
					SUPERVISOR = 'supervisorhere'
					NICK_NAME = 'nicknamehere'
					FIRST_NAME = 'firstnamehere'
					LAST_NAME = 'lastnamehere'
					CsvTitle = 'sync1'
					CsvDisplayName = 'sync2'
				}
			}

			mock 'FindUserMatch'

			mock 'GetCsvIdField' {
				[pscustomobject]@{
					Field = 'PERSON_NUM'
					Value = '1'
				}
			}

			mock 'Write-Output'

			mock 'TestIsValidAdAttribute' {
				$true
			}

			mock 'TestFieldMapIsValid' {
				$true
			}

			mock 'New-CompanyAdUser'

			mock 'Get-AdUser' {
				[pscustomobject]@{
					DistinguishedName = 'CN=manager'
				}
			}
		#endregion

		$parameterSets = @(
			@{
				Label = 'ReportOnly'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
					ReportOnly = $true
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Single sync /single match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Multi sync/Multi match field'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldSyncMap = @{ 
						'CsvTitle' = 'ADTitle'
						'CSVDisplayName' = 'ADDisplayName'
						({ if (-not $_.CsvNullField) { 'CsvNonNullField' }}) = 'ADDisplayName3'
					}
					FieldMatchMap = @{ 
						PERSON_NUM = 'EmployeeId'
						AD_LOGON = 'samAcountName'
					}
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 3
						}
					}
				}
			}
			@{
				Label = 'Exclude'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ PERSON_NUM = 'EmployeeId' }
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					Exclude = @{ ExcludeCol = 'excludeme' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Multi-string match'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ 
						@( 'FIRST_NAME','LAST_NAME') = @('givenName','surName') 
					}
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'Multi-string conditional match'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ @({ if ($_.'NICK_NAME') { 'NICK_NAME' } else { 'FIRST_NAME'} },'LAST_NAME') = @('givenName','surName') }
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
			@{
				Label = 'FieldValueMap'
				Parameters = @{
					CsvFilePath = 'C:\log.csv'
					FieldMatchMap = @{ 'PERSON_NUM' = 'employeeId' }
					FieldSyncMap = @{ 'CsvTitle' = 'ADTitle' }
					FieldValueMap = @{ 'SUPERVISOR' = { $supId = $_.'SUPERVISOR_ID'; (Get-AdUser -Filter "EmployeeId -eq '$supId'").DistinguishedName }}
				}
				Expect = @{
					Execution = @{
						TestIsValidAdAttribute = @{
							RunTimes = 1
						}
					}
				}
			}
		)

		$testCases = $parameterSets

		foreach ($testCase in $testCases) {

			$parameters = $testCase.Parameters
			$expect = $testCase.Expect

			context $testCase.Label {

				if ($parameters.ContainsKey('Exclude')) {

					context 'when excluding a CSV column' {

						$null = & $commandName @parameters

						context 'when a header does not exist' {
						
							mock 'TestCsvHeaderExists' {
								$false
							} -ParameterFilter { 'excludecol' -in $Header }

							it 'should throw an exception' {
								$params = @{} + $parameters
								{ & $commandName @params } | should throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file'
							}
						
						}

						context 'when all headers exist' {
						
							mock 'TestCsvHeaderExists' {
								$true
							}

							$null = & $commandName @parameters

							it 'should pass Exclude to Get-CompanyCsvUser' {

								$assMParams = @{
									CommandName = 'Get-CompanyCsvUser'
									Times = 1
									Exactly = $true
									ParameterFilter = { 
										$PSBoundParameters.Exclude.Keys -eq 'ExcludeCol' -and
										$PSBoundParameters.Exclude.Values -eq 'excludeme'
									}
								}
								Assert-MockCalled @assMParams
								
							}
						}
					}
				}

				context 'Shared tests' {
				
					$null = & $commandName @parameters

					it 'should only test string AD attributes in FieldSyncMap' {

						$thisFunc = $expect.Execution.TestIsValidAdAttribute
						
						$assMParams = @{
							CommandName = 'TestIsValidAdAttribute'
							Times = $thisFunc.RunTimes
							Exactly = $true
							ExclusiveFilter = { $PSBoundParameters.Name -is 'string' }
						}
						Assert-MockCalled @assMParams
					}
				
				}

				context 'when at least one AD attribute in FieldSyncMap is not available' {

					mock 'TestIsValidAdAttribute' {
						$false
					}
				
					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'One or more AD attributes'
					}
				
				}

				context 'when an invalid header is found in a field map' {

					mock 'TestFieldMapIsValid' {
						$false
					}
				
					it 'should throw an exception' {
					
						{ & $commandName @parameters } | should throw 'Invalid attribute found'
					}
				
				}

				context 'when no AD users are found' {
					
					mock 'Get-CompanyAdUser'

					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'No AD users found'
					}
				}

				context 'when no CSV users are found' {
					
					mock 'Get-CompanyCsvUser'

					it 'should throw an exception' {
					
						$params = @{} + $parameters
						{ & $commandName @params } | should throw 'No CSV users found'
					}
					
				}

				context 'when at least one AD user and one CSV user is found' {

					$result = & $commandName @parameters
					
					it 'should return nothing' {
						$result | should benullorempty
					}
					
					context 'when a user match cannot be found' {

						mock 'FindUserMatch'
					
						context 'when no CSV ID fields can be found' {

							mock 'GetCsvIdField'

							$null = & $commandName @parameters

							it 'write a warning' {
							
								$assMParams = @{
									CommandName = 'Write-Warning'
									Times = 1
									Exactly = $true
									ExclusiveFilter = {
										$PSBoundParameters.Message -match 'No CSV id fields were found'
									}
								}
								Assert-MockCalled @assMParams
							}			
						}

						context 'when at least one CSV ID field can be found' {

							context 'when a populated CSV ID field exists' {
								
								mock 'GetCsvIdField' {
									[pscustomobject]@{
										Field = $null
										Value = 'val1'
									}
									[pscustomobject]@{
										Field = $null
										Value = 'val2'
									}
									[pscustomobject]@{
										Field = 'populatedfield1'
										Value = 'val1'
									}
								}

								$null = & $commandName @parameters
								
								it 'should pass the ID as the CSV id field for WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.CSVIdentifierField -eq 'populatedfield1' 
										}
									}
									Assert-MockCalled @assMParams
								}
							
							}

							context 'when no CSV ID fields are populated' {
							
								mock 'GetCsvIdField' {
									[pscustomobject]@{
										Field = 'field1'
										Value = $null
									}
									[pscustomobject]@{
										Field = 'field2'
										Value = $null
									}
								}

								$null = & $commandName @parameters

								it 'should pass N/A as the CSV id field for WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.CsvIdentifierValue -eq 'N/A' -and
											$PSBoundParameters.CSVIdentifierField -eq 'field1,field2'
										}
									}
									Assert-MockCalled @assMParams
								}
							}
						}
					}

					context 'when a user match can be found' {

						mock 'FindUserMatch' {
							[pscustomobject]@{
								MatchedAdUser = $script:testAdUser
								CSVAttemptedMatchIds = 'PERSON_NUM'
								ADAttemptedMatchIds = 'EmployeeId'
							}
						}
					
						context 'when an attribute mismatch is found' {

							mock 'FindAttributeMismatch' {
								@{
									CSVField = @{'x' = 'y'}
									ActiveDirectoryAttribute = @{ 'z' = 'i' }
									ADShouldBe = @{ 'z' = 'y' }
								}
							}

							if ($parameters.ContainsKey('ReportOnly')) {
								context 'when only reporting' {

									$null = & $commandName @parameters

									it 'should not attempt to sync the user' {
									
										$assMParams = @{
											CommandName = 'SyncCompanyUser'
											Times = 0
											Exactly = $true
										}
										Assert-MockCalled @assMParams
									}
								}
							} else {
								context 'when syncing' {

									$null = & $commandName @parameters

									it 'should sync the expected user' {

										$assMParams = @{
											CommandName = 'SyncCompanyUser'
											Times = 1
											Exactly = $true
											ParameterFilter = { 
												$PSBoundParameters.Identity -eq 'samval' -and
												$PSBoundParameters.CsvUser.'AD_LOGON' -eq 'nameval' -and
												$PSBoundParameters.CsvUser.'PERSON_NUM' -eq "1" -and
												$PSBoundParameters.ActiveDirectoryAttributes.z -eq 'y'
											}
										}
										Assert-MockCalled @assMParams
									}
								}
							}
						}

						context 'when all attributes are in sync' {

							mock 'FindAttributeMismatch'

							$null = & $commandName @parameters
						
							it 'should pass the expected attributes to WriteLog' {

									$assMParams = @{
										CommandName = 'WriteLog'
										Times = 1
										Exactly = $true
										ParameterFilter = { 
											$PSBoundParameters.Attributes.CSVAttributeName -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.CSVAttributeValue -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.ADAttributeName -eq 'AlreadyInSync' -and
											$PSBoundParameters.Attributes.ADAttributeValue -eq 'AlreadyInSync'
										}
									}
									Assert-MockCalled @assMParams
								}
						}
					}
				}
			}
		}
	}

	Remove-Variable -Name allAdUsers -Scope Script
	Remove-Variable -Name allCsvUsers -Scope Script
}