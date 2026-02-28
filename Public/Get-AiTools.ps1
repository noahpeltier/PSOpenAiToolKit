function Get-AiTools {
    [CmdletBinding()]
    param(
        [string]$Type,
        [switch]$FunctionOnly
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    $tools = $script:CurrentAi.GetTools()

    if ($FunctionOnly) {
        $tools = @($tools | Where-Object { $_.Type -eq "function" })
    }

    if (-not [string]::IsNullOrWhiteSpace($Type)) {
        $tools = @($tools | Where-Object { $_.Type -eq $Type })
    }

    return $tools
}
