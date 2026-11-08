# Choose Your Adventures · Teacher Alex

Site estático com as histórias de escolhas (Choose Your Adventure) do Teacher Alex, para abrir em qualquer PC durante a aula.

- `index.html`: o seletor, com capa, nível, partes e finais de cada história.
- `aventuras/`: uma página por história, sem servidor, progresso guardado no navegador.
- `capas/`: imagens do seletor; fontes e licenças em `capas/FONTES.md`.

As fontes ficam em `../Apostilas/01-OFICINA/graded-reader-studio/`; as entregas vêm
do catálogo da Mesa. Não existe mais dependência de `Desktop/apostilas`.

## Conferir e atualizar

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sincronizar.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sincronizar.ps1 -Sincronizar
```

O primeiro comando é **somente leitura**, sem Git, escrita ou rede. O segundo
confere o lote inteiro e atualiza a cópia local. A localização das aventuras vem de
`../Apostilas/01-OFICINA/motor/catalogo_mesa.json`, no endereço único da Mesa.

As três histórias `dont-write`, `dont-close` e `dont-go-out` ainda não têm fontes
de autoria no estúdio. Se existir um HTML completo correspondente em Downloads,
ele é usado; caso contrário, a cópia atual em `aventuras/` é verificada e preservada,
com aviso explícito de que não foi reconstruída. Se nem essa cópia existir, o lote
para antes de escrever. Não há varredura de Downloads: são três nomes explícitos.
Se forem cadastradas como aventuras na Mesa, o catálogo passa a prevalecer.
`-Apostilas <pasta>` e `-Downloads <pasta>` permitem indicar as fontes numa bancada.

Uma fonte ausente, HTML incompleto ou divergência entre o índice e a lista de aventuras
interrompe antes de qualquer cópia. Capas e histórias são preparadas juntas;
uma falha de substituição restaura as entregas anteriores. O script não reconstrói
o seletor: se a lista mudar, atualize `index.html` antes de sincronizar.

Uma interrupção externa ou falha de restauração deixa `.sincronizar-pendente/`,
com `recuperacao.json` e backups. A próxima execução fica bloqueada: primeiro
conferir/restaurar os destinos indicados, depois remover a trava. Não apagar
essa pasta como temporário comum nem prosseguir por cima dela.

## Publicar, somente quando solicitado

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sincronizar.ps1 -Publicar
```

`-Publicar` inclui sincronização, commit e push. Exige este repositório limpo antes
de começar e adiciona somente os caminhos alterados pelo lote. Falha de Git interrompe
com erro; “Publicado” só aparece após push concluído. Se o push falhar depois do
commit, ele permanece local para repetir o push quando a causa estiver resolvida.
O Git precisa estar no `PATH`; caso contrário, use `-GitExecutavel <caminho-do-git.exe>`.

## Classificação e validação

- `sincronizar.ps1`: conferência local por padrão; `-Sincronizar` escreve somente nesta
  pasta; `-Publicar` também altera Git/remoto. Nunca envia mensagens a alunos.
- `tests/test_sincronizar.py`: testes locais em cópias temporárias fictícias; valida
  conferência, sincronização, caminhos e falhas, sem tocar entregas reais. Executar:

```text
python -B -X utf8 -m unittest discover -s tests -v
```

Os testes usam o Windows PowerShell instalado. Nenhuma instalação global.
