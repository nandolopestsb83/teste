# Compilar o APK sem instalar nada

1. Crie uma conta em github.com e um repositório novo (pode ser privado), com o branch `main`.
2. Envie o conteúdo desta pasta para ele (botão "Add file > Upload files" arrastando tudo,
   inclusive a pasta oculta `.github`; ou use git).
3. Aba **Actions** > "Compilar APK" > **Run workflow**. Leva uns 5 a 10 minutos.
4. Ao terminar, abra a execução e baixe **btmesh-apk** (em Artifacts). Descompacte o .zip.
5. Mande o `app-release.apk` para os celulares e instale
   (Configurações > permitir instalar de fontes desconhecidas para o app usado para abrir o arquivo).

O passo "Testes do núcleo" roda a simulação A-B-C; se ela falhar, a Action para e mostra o erro.
Se a compilação falhar, copie o log de erro e me mande.

Para compilar no seu computador: instale Flutter e Java 17, depois `bash montar.sh`.
