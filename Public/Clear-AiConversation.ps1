function Clear-AiConversation {
    if (-not $script:CurrentAi) {
        throw "No OpenAi instance found. Run New-Ai first."
    }

    $script:CurrentAi.Forget()
}
