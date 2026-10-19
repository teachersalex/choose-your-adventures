# Copia as aventuras, as capas e o seletor de novo e publica. Rodar nesta pasta:
#   powershell -ExecutionPolicy Bypass -File .\sincronizar.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$mesa = "C:\Users\alexm\Desktop\apostilas\00-MESA-DO-ALEX\02-EM-REVISAO\Leituras interativas"
$dl = "C:\Users\alexm\Downloads"
$studio = "C:\Users\alexm\Desktop\apostilas\01-OFICINA\graded-reader-studio"
$fontes = @{
  "dont-read" = "$mesa\Don't Read.html"; "dont-stay" = "$mesa\Don't Stay.html"; "dont-sign" = "$mesa\Don't Sign.html"
  "dont-invite" = "$mesa\Don't Invite Him In.html"; "the-message" = "$mesa\The Message.html"
  "dont-tell" = "$mesa\Dont_Tell_Him_Your_Name_A2.html"; "dont-tell-anyone" = "$mesa\Don't Tell Anyone.html"
  "dont-lose" = "$mesa\Don't Lose Anyone.html"; "dont-lie" = "$mesa\Don't Lie.html"
  "vanessa-always-wins" = "$mesa\Vanessa Always Wins.html"; "salt-and-sugar" = "$mesa\Salt_and_Sugar_A2.html"
  "dont-write" = "$dl\dont-write.standalone.html"; "dont-close" = "$dl\dont-close.standalone.html"; "dont-go-out" = "$dl\dont-go-out.standalone.html"
}
foreach ($slug in $fontes.Keys) {
  $src = $fontes[$slug]
  if (Test-Path $src) { Copy-Item $src "aventuras\$slug.html" -Force } else { Write-Warning "Fonte ausente, mantida a cópia atual: $src" }
}
Copy-Item "$studio\capas\*" "capas\" -Force
# O index.html é gerado a partir do seletor local; se o seletor mudou, gere de novo com o Claude.
git add -A
if (git status --porcelain) { git commit -m "Atualiza aventuras e capas" | Out-Null; git push; Write-Host "Publicado." } else { Write-Host "Nada mudou." }
