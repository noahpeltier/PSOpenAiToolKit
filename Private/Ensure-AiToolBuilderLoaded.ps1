function Ensure-AiToolBuilderLoaded {
    if (Get-Command -Name New-ChatCompletionFunction -ErrorAction SilentlyContinue) {
        return
    }

    $toolBuilderPath = Join-Path -Path $PSScriptRoot -ChildPath "ChatCompletionFunction.ps1"
    if (-not (Test-Path -Path $toolBuilderPath)) {
        throw "Could not find ChatCompletionFunction.ps1 at '$toolBuilderPath'."
    }

    . $toolBuilderPath

    if (-not (Get-Command -Name New-ChatCompletionFunction -ErrorAction SilentlyContinue)) {
        throw "Failed to load New-ChatCompletionFunction from '$toolBuilderPath'."
    }
}
