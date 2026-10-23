$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stringsPath = Join-Path $repositoryRoot 'android/app/src/main/res/values/strings.xml'
$xml = [xml](Get-Content -LiteralPath $stringsPath -Raw)
$clientIdNode = $xml.resources.string | Where-Object { $_.name -eq 'truecaller_client_id' } | Select-Object -First 1
$clientId = if ($null -ne $clientIdNode) { $clientIdNode.InnerText.Trim() } else { '' }

if ([string]::IsNullOrWhiteSpace($clientId) -or $clientId -match '^REPLACE_') {
    throw 'Set a valid Truecaller client ID in android/app/src/main/res/values/strings.xml first.'
}

$environmentPath = Join-Path $repositoryRoot 'functions/.env.autointel-ai-app'
$environmentContent = "TRUECALLER_CLIENT_ID=$clientId`n"
[System.IO.File]::WriteAllText(
    $environmentPath,
    $environmentContent,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output 'Synced Truecaller client ID to the ignored Firebase Functions environment file.'
