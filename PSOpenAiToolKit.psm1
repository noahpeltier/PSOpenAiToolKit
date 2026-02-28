$moduleRoot = Split-Path -Parent $PSCommandPath

foreach ($classFile in (Get-ChildItem -Path (Join-Path $moduleRoot "Classes") -Filter "*.ps1" -File | Sort-Object Name)) {
    . $classFile.FullName
}

foreach ($privateFile in (Get-ChildItem -Path (Join-Path $moduleRoot "Private") -Filter "*.ps1" -File | Sort-Object Name)) {
    . $privateFile.FullName
}

foreach ($publicFile in (Get-ChildItem -Path (Join-Path $moduleRoot "Public") -Filter "*.ps1" -File | Sort-Object Name)) {
    . $publicFile.FullName
}

Export-ModuleMember -Function @(
    "New-Ai",
    "Get-Ai",
    "Invoke-OpenAiMethod",
    "Get-AiResponse",
    "Get-AiResponseStream",
    "Add-AiTool",
    "Get-AiTools",
    "Remove-AiTool",
    "Register-AiToolHandler",
    "Set-AiInstructions",
    "Set-AiReasoningEffort",
    "Set-AiStoreResponses",
    "Set-AiLegacyToolAutoInvoke",
    "Clear-AiConversation"
)
