param([switch]$Synthesize)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildDir = Join-Path $projectRoot '.verification\optimized_i2c'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$vivadoBin = Split-Path (Get-Command vivado.bat -ErrorAction Stop).Source -Parent
$rtlDir = Join-Path $projectRoot 'i2c_sensor_oled_driver.srcs\sources_1\new'
$rtlNames = @('i2c_master_write', 'spi_master_transfer', 'sensor_request_master', 'request_button', 'oled_sensor_display', 'sensor_network_master')
$rtlPaths = @($rtlNames | ForEach-Object { Join-Path $rtlDir ($_.ToString() + '.v') })

# Adapt copies only: original tests and all original .v files stay untouched.
foreach ($name in @('tb_sensor_network_master', 'tb_i2c_sensor_errors')) {
    $source = Get-Content -LiteralPath (Join-Path $projectRoot ('tests\' + $name + '.sv')) -Raw
    $source = $source.Replace('slave_i2c.state == 6', 'slave_i2c.state == slave_i2c.TX')
    $source = $source.Replace('slave.state == 6', 'slave.state == slave.TX')
    Set-Content -LiteralPath (Join-Path $buildDir ($name + '.sv')) -Value $source -Encoding utf8
}
Push-Location $buildDir
try {
    & (Join-Path $vivadoBin 'xvlog.bat') --sv @rtlPaths `
        (Join-Path $PSScriptRoot 'i2c_sensor_read_master.sv') `
        (Join-Path $PSScriptRoot 'i2c_sensor_slave.sv') `
        (Join-Path $projectRoot 'slave_basys3\rtl\spi_sensor_slave.v') `
        (Join-Path $projectRoot 'slave_basys3\original\sensor_reg_bank.v') `
        (Join-Path $buildDir 'tb_sensor_network_master.sv') `
        (Join-Path $buildDir 'tb_i2c_sensor_errors.sv') `
        (Join-Path $PSScriptRoot 'tb_optimized_i2c.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog compilation failed' }
    $cases = @(
        @{ Top='tb_sensor_network_master'; Name='network_32'; Generic='TEST_HEIGHT=32'; Pass='PASS: paired SPI/I2C RTL' },
        @{ Top='tb_sensor_network_master'; Name='network_64'; Generic='TEST_HEIGHT=64'; Pass='PASS: paired SPI/I2C RTL' },
        @{ Top='tb_i2c_sensor_errors'; Name='errors'; Generic=$null; Pass='PASS: I2C error paths' },
        @{ Top='tb_optimized_i2c'; Name='timing_100k'; Generic='TEST_I2C_HZ=100000'; Pass='PASS: optimized I2C' },
        @{ Top='tb_optimized_i2c'; Name='timing_400k'; Generic='TEST_I2C_HZ=400000'; Pass='PASS: optimized I2C' }
    )
    foreach ($test in $cases) {
        $options = @($test.Top, '-s', $test.Name)
        if ($test.Generic) {
            $file = Join-Path $buildDir ($test.Name + '.f')
            Set-Content -LiteralPath $file -Encoding ascii -Value ('--generic_top "{0}"' -f $test.Generic)
            $options += @('-f', $file)
        }
        & (Join-Path $vivadoBin 'xelab.bat') @options
        if ($LASTEXITCODE -ne 0) { throw ('Elaboration failed: ' + $test.Name) }
        & (Join-Path $vivadoBin 'xsim.bat') $test.Name -runall -log ($test.Name + '.log')
        if ($LASTEXITCODE -ne 0) { throw ('Simulation failed: ' + $test.Name) }
        $result = Get-Content -LiteralPath ($test.Name + '.log') -Raw
        if (!$result.Contains($test.Pass) -or $result -match 'Fatal:') {
            throw ('Self-check failed: ' + $test.Name)
        }
    }
    if ($Synthesize) {
        & (Join-Path $vivadoBin 'vivado.bat') -mode batch -source (Join-Path $PSScriptRoot 'compare_synthesis.tcl')
        if ($LASTEXITCODE -ne 0) { throw 'Synthesis comparison failed' }
    }
    Write-Output 'PASS: all optimized I2C tests'
} finally { Pop-Location }
