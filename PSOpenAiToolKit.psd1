@{
    RootModule = "PSOpenAiToolKit.psm1"
    ModuleVersion = "0.1.0"
    GUID = "a97f28d9-f7f5-4952-8e5f-cf123183b346"
    Author = "PSOpenAiToolKit Contributors"
    CompanyName = "Community"
    Copyright = "(c) PSOpenAiToolKit Contributors. All rights reserved."
    Description = "PowerShell toolkit for OpenAI Responses API workflows, streaming, tools, and raw endpoint access."
    PowerShellVersion = "7.2"

    FunctionsToExport = @(
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

    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @("OpenAI", "PowerShell", "AI", "Streaming", "ResponsesAPI")
            Prerelease = "alpha"
        }
    }
}
