$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildDir = Join-Path $projectRoot '.verification'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$vivadoBin = Split-Path (Get-Command vivado.bat -ErrorAction Stop).Source -Parent
$rtlDir = Join-Path $projectRoot 'i2c_sensor_oled_driver.srcs\sources_1\new'
$rtlNames = @('i2c_master_write', 'spi_master_transfer', 'i2c_sensor_read_master', 'sensor_request_master', 'request_button', 'oled_sensor_display', 'sensor_network_master')
$rtlPaths = $rtlNames | ForEach-Object { Join-Path $rtlDir ($_.ToString() + '.v') }
Push-Location $buildDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') --sv @rtlPaths (Join-Path $projectRoot 'slave_basys3\rtl\spi_sensor_slave.v') (Join-Path $projectRoot 'slave_basys3\rtl\i2c_sensor_slave.v') (Join-Path $projectRoot 'slave_basys3\original\sensor_reg_bank.v') (Join-Path $projectRoot 'tests\tb_sensor_network_master.sv') (Join-Path $projectRoot 'tests\tb_i2c_sensor_errors.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog compilation failed' }
    foreach ($height in @(32,64)) {
        $snapshot = 'sensor_master_tests_' + $height
        # Keep '=' inside xelab's own option file; cmd/batch strips it from
        # an unquoted argument assembled by PowerShell's legacy invocation.
        $optionsFile = Join-Path $buildDir ('elaborate_' + $height + '.f')
        Set-Content -LiteralPath $optionsFile -Encoding ascii -Value ('--generic_top "TEST_HEIGHT={0}"' -f $height)
        & (Join-Path $vivadoBin 'xelab.bat') tb_sensor_network_master -f $optionsFile -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "xelab elaboration failed ($height rows)" }
        & (Join-Path $vivadoBin 'xsim.bat') $snapshot -runall -log ($snapshot + '.log')
        if ($LASTEXITCODE -ne 0) { throw 'xsim execution failed' }
        $result = Get-Content -Raw (Join-Path $buildDir ($snapshot + '.log'))
        if ($result -notmatch 'PASS: paired SPI/I2C RTL' -or $result -match 'Fatal:') { throw 'Self-checking testbench failed' }
    }
    & (Join-Path $vivadoBin 'xelab.bat') tb_i2c_sensor_errors -s i2c_error_tests
    if ($LASTEXITCODE -ne 0) { throw 'I2C error test elaboration failed' }
    & (Join-Path $vivadoBin 'xsim.bat') i2c_error_tests -runall -log i2c_error_tests.log
    $errorsResult = Get-Content -Raw (Join-Path $buildDir 'i2c_error_tests.log')
    if ($LASTEXITCODE -ne 0 -or $errorsResult -notmatch 'PASS: I2C error paths' -or $errorsResult -match 'Fatal:') { throw 'I2C error test failed' }
} finally { Pop-Location }
