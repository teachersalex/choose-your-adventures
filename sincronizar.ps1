# Default: check only. See README.md before synchronizing or publishing.
[CmdletBinding()]
param(
    [switch]$Sincronizar,
    [switch]$Publicar,
    [string]$Apostilas,
    [string]$Downloads = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'),
    [string]$GitExecutavel = 'git'
)
$ErrorActionPreference = 'Stop'
$pastaScript = Split-Path $MyInvocation.MyCommand.Path -Parent
$raiz = [IO.Path]::GetFullPath($pastaScript)
if (-not $Apostilas) { $Apostilas = Join-Path (Split-Path $raiz -Parent) 'Apostilas' }
$trava = Join-Path $raiz '.sincronizar-pendente'
$baseApostilas = [IO.Path]::GetFullPath($Apostilas)
$mesa = Join-Path $baseApostilas '00-MESA-DO-ALEX'
$studio = Join-Path $baseApostilas '01-OFICINA/graded-reader-studio'
$catalogo = Join-Path $baseApostilas '01-OFICINA/motor/catalogo_mesa.json'

function Testar-Dentro([string]$Caminho, [string]$Base) {
    $absoluto = [IO.Path]::GetFullPath($Caminho)
    $prefixo = [IO.Path]::GetFullPath($Base).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $absoluto.StartsWith($prefixo, [StringComparison]::OrdinalIgnoreCase)) { throw "Caminho fora da area esperada: $Caminho" }
    $atual = $absoluto
    while ($atual.Length -ge $prefixo.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $atual) {
            if ((Get-Item -LiteralPath $atual -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link de sistema nao permitido: $atual" }
        }
        $proximo = Split-Path $atual -Parent
        if (-not $proximo -or $proximo -eq $atual) { break }
        $atual = $proximo
    }
    return $absoluto
}
function Invoke-SiteGit([string[]]$Argumentos) {
    $executavel = (Get-Command $GitExecutavel -CommandType Application -ErrorAction Stop).Source
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $executavel
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.WorkingDirectory = $raiz
    # Windows native quoting: double backslashes only before quotes or the final quote.
    $info.Arguments = (@(@('-C', $raiz) + $Argumentos) | ForEach-Object {
        '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $processo = New-Object Diagnostics.Process
    $processo.StartInfo = $info
    try {
        $null = $processo.Start()
        $texto = $processo.StandardOutput.ReadToEndAsync()
        $erro = $processo.StandardError.ReadToEndAsync()
        if (-not $processo.WaitForExit(180000)) { $processo.Kill(); throw 'Git excedeu o tempo de espera.' }
        $saida = $texto.Result
        if ($processo.ExitCode -ne 0) { throw "Git falhou ($($processo.ExitCode)): $($Argumentos -join ' ')`n$($erro.Result)" }
        return $saida.TrimEnd()
    } finally { $processo.Dispose() }
}
function Limpar-Trava {
    $null = Testar-Dentro $trava $raiz
    foreach ($f in Get-ChildItem -LiteralPath $trava -File -Force) { Remove-Item -LiteralPath $f.FullName -Force }
    [IO.Directory]::Delete($trava) # non-recursive; unexpected directories stop cleanup
}
if (Test-Path -LiteralPath $trava) { throw "Sincronizacao em andamento ou interrompida. Examine $trava antes de repetir." }
$dados = Get-Content -LiteralPath $catalogo -Raw -Encoding UTF8 | ConvertFrom-Json
$fontes = @{}
foreach ($item in $dados.materiais) {
    if (-not $item.aventura) { continue }
    $slug = [string]$item.aventura
    if ($slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $fontes.ContainsKey($slug)) { throw "Slug invalido ou repetido: $slug" }
    if ([IO.Path]::IsPathRooted($item.arquivo) -or ($item.arquivo -split '[\\/]') -contains '..') { throw "Destino invalido no catalogo: $($item.arquivo)" }
    if ($item.arquivo -notmatch '^(02-EM-REVISAO|03-PRONTOS-PARA-USAR)[\\/].+\.html$') { throw "Aventura fora das areas de entrega: $slug" }
    $fontes[$slug] = Testar-Dentro (Join-Path $mesa $item.arquivo) $mesa
}
# These three sources have not yet been imported into the studio/catalogue.
$preservadas = @()
foreach ($slug in @('dont-write', 'dont-close', 'dont-go-out')) {
    if ($fontes.ContainsKey($slug)) { continue }
    $exportado = Join-Path $Downloads ($slug + '.standalone.html')
    if (Test-Path -LiteralPath $exportado -PathType Leaf) { $fontes[$slug] = $exportado }
    else {
        $fontes[$slug] = Testar-Dentro (Join-Path $raiz "aventuras/$slug.html") $raiz
        $preservadas += $slug
    }
}
$indice = Get-Content -LiteralPath (Join-Path $raiz 'index.html') -Raw -Encoding UTF8
$listadas = @([regex]::Matches($indice, 'href="aventuras/([^"/]+)\.html"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (-not $listadas.Count) { throw 'O index.html nao possui links de aventuras.' }
if (@(Compare-Object @($fontes.Keys | Sort-Object) @($listadas)).Count) { throw 'O index.html e as fontes nao listam as mesmas aventuras. Atualize o seletor antes de sincronizar.' }
$plano = New-Object 'System.Collections.Generic.List[object]'
foreach ($slug in ($fontes.Keys | Sort-Object)) { $plano.Add([pscustomobject]@{ Origem=$fontes[$slug]; Relativo="aventuras/$slug.html" }) }
$pastaCapas = Join-Path $studio 'capas'
foreach ($capa in Get-ChildItem -LiteralPath $pastaCapas -File) {
    $null = Testar-Dentro $capa.FullName $pastaCapas
    $plano.Add([pscustomobject]@{ Origem=$capa.FullName; Relativo='capas/' + $capa.Name })
}
foreach ($capa in @([regex]::Matches($indice, 'src="(capas/[^"]+)"') | ForEach-Object { [Uri]::UnescapeDataString($_.Groups[1].Value) })) {
    if ($capa -notin @($plano | ForEach-Object { $_.Relativo })) { throw "Capa do seletor sem fonte: $capa" }
}
# Read every input before creating the lock or writing a destination.
$mudancas = New-Object 'System.Collections.Generic.List[object]'
foreach ($item in $plano) {
    if (-not (Test-Path -LiteralPath $item.Origem -PathType Leaf)) { throw "Fonte ausente: $($item.Origem). Nenhuma copia foi feita." }
    $alvo = Testar-Dentro (Join-Path $raiz $item.Relativo) $raiz
    $novo = [IO.File]::ReadAllBytes($item.Origem)
    if ($item.Relativo.StartsWith('aventuras/') -and [Text.Encoding]::UTF8.GetString($novo) -notmatch '(?is)<html(?:\s|>)') { throw "A fonte nao e um HTML completo: $($item.Origem)" }
    $anterior = $null
    if (Test-Path -LiteralPath $alvo -PathType Leaf) { $anterior = [IO.File]::ReadAllBytes($alvo) }
    if ($null -eq $anterior -or [Convert]::ToBase64String($novo) -cne [Convert]::ToBase64String($anterior)) {
        $mudancas.Add([pscustomobject]@{ Alvo=$alvo; Relativo=$item.Relativo; Novo=$novo; Anterior=$anterior; Backup=$null; Pronto=$null })
    }
}
Write-Output "Conferidas $($fontes.Count) aventuras e $($plano.Count - $fontes.Count) recursos de capa; $($mudancas.Count) arquivos diferentes."
if ($preservadas.Count) { Write-Output "Copias preservadas no site, sem fonte nova em Downloads: $($preservadas -join ', '). Nao foram reconstruidas." }
if (-not ($Sincronizar -or $Publicar)) { Write-Output 'Somente leitura. Use -Sincronizar para atualizar a copia local; -Publicar inclui commit e push.'; return }
if ($Publicar) {
    $topo = Invoke-SiteGit @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($topo) -ne $raiz) { throw 'O destino nao e a raiz do repositorio esperado.' }
    if (Invoke-SiteGit @('status', '--porcelain')) { throw 'Ha mudancas locais no site. Resolva-as antes de publicar; nada sera incluido automaticamente.' }
}
if ($mudancas.Count) {
    $null = New-Item -ItemType Directory -Path $trava -ErrorAction Stop
    $tentados = New-Object 'System.Collections.Generic.List[object]'
    $preservar = $false
    try {
        $n = 0
        foreach ($item in $mudancas) {
            $item.Pronto = Join-Path $trava ("{0:D4}.new" -f $n)
            [IO.File]::WriteAllBytes($item.Pronto, $item.Novo)
            if ($null -ne $item.Anterior) { $item.Backup = Join-Path $trava ("{0:D4}.bak" -f $n); [IO.File]::WriteAllBytes($item.Backup, $item.Anterior) }
            $n++
        }
        @($mudancas | Select-Object Alvo, Backup, Pronto) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $trava 'recuperacao.json') -Encoding UTF8
        try {
            foreach ($item in $mudancas) {
                $atual = $null
                if (Test-Path -LiteralPath $item.Alvo) { $atual = [IO.File]::ReadAllBytes($item.Alvo) }
                if (($null -eq $atual) -ne ($null -eq $item.Anterior) -or ($null -ne $atual -and [Convert]::ToBase64String($atual) -cne [Convert]::ToBase64String($item.Anterior))) { throw "Destino mudou durante a preparacao: $($item.Alvo)" }
                $null = [IO.Directory]::CreateDirectory((Split-Path $item.Alvo -Parent))
                $tentados.Add($item)
                if ($null -ne $item.Anterior) { [IO.File]::Replace($item.Pronto, $item.Alvo, [NullString]::Value) } else { [IO.File]::Move($item.Pronto, $item.Alvo) }
            }
        } catch {
            $erroOriginal = $_
            $falhas = @()
            for ($i = $tentados.Count - 1; $i -ge 0; $i--) {
                $item = $tentados[$i]
                try {
                    if ($item.Backup) {
                        if ((Test-Path -LiteralPath $item.Alvo -PathType Leaf) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.Alvo)) -ceq [Convert]::ToBase64String($item.Anterior)) { continue }
                        $restauro = Join-Path $trava 'restauro.tmp'
                        [IO.File]::Copy($item.Backup, $restauro, $true)
                        if (Test-Path -LiteralPath $item.Alvo) { [IO.File]::Replace($restauro, $item.Alvo, [NullString]::Value) } else { [IO.File]::Move($restauro, $item.Alvo) }
                    } elseif (Test-Path -LiteralPath $item.Alvo) { Remove-Item -LiteralPath $item.Alvo -Force }
                } catch { $falhas += $_.Exception.Message }
            }
            if ($falhas.Count) { $preservar = $true; throw "Falha de restauracao. Preserve os backups em $trava. $($falhas -join '; ')" }
            throw $erroOriginal
        }
    } finally { if (-not $preservar) { Limpar-Trava } }
}
Write-Output 'Copia local sincronizada.'
if ($Publicar) {
    if ($mudancas.Count) {
        $null = Invoke-SiteGit (@('add', '--') + @($mudancas | ForEach-Object { $_.Relativo }))
        $null = Invoke-SiteGit @('commit', '-m', 'Atualiza aventuras e capas')
    }
    $null = Invoke-SiteGit @('push')
    Write-Output 'Publicado: push concluido.'
}
