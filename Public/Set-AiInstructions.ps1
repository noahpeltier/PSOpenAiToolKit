function Set-AiInstructions {
    param(
        [string]$Instructions,
        [switch]$Clear
    )

    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    if ($Clear) {
        $script:CurrentAi.ClearInstructions()
        return
    }

    $script:CurrentAi.SetInstructions($Instructions)
}
