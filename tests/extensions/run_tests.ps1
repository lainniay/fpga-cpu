param(
    [Parameter(Mandatory = $true)]
    [string]$VivadoBin
)
$ErrorActionPreference = 'Stop'
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$simTcl = (Join-Path $PSScriptRoot 'run_sim.tcl').Replace('\', '/')
$rtlFiles = @{
    branch_predictor = Join-Path $projectRoot 'cdp_ede_local-master\mycpu_env\myCPU\branch_predictor.v'
    uart_tx = Join-Path $projectRoot 'cdp_ede_local-master\mycpu_env\soc_verify\soc_bram\rtl\UART\uart_tx.v'
}
foreach ($moduleName in @('branch_predictor', 'uart_tx')) {
    $runDir = Join-Path $PSScriptRoot "results\$moduleName"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    Push-Location $runDir
    try {
        & "$VivadoBin\xvlog.bat" $rtlFiles[$moduleName]
        if ($LASTEXITCODE -ne 0) { throw "RTL compilation failed: $moduleName" }
        & "$VivadoBin\xvlog.bat" --sv (Join-Path $PSScriptRoot "tb_$moduleName.sv")
        if ($LASTEXITCODE -ne 0) { throw "Testbench compilation failed: $moduleName" }
        & "$VivadoBin\xelab.bat" "tb_$moduleName" --debug typical --snapshot "sim_$moduleName" --timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $moduleName" }
        & "$VivadoBin\xsim.bat" "sim_$moduleName" --tclbatch $simTcl --wdb "$moduleName.wdb" --log simulate.log
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $moduleName" }
        $simulationLog = Get-Content -Raw -LiteralPath 'simulate.log'
        if ($simulationLog -notmatch "PASS tb_$moduleName " -or $simulationLog -match 'Fatal:|FATAL|ERROR:') {
            throw "Simulation did not pass: $moduleName"
        }
    } finally {
        Pop-Location
    }
}
Write-Host 'PASS: branch_predictor and uart_tx simulations completed.'
