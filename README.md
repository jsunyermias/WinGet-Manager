# WinGet-Manager
PowerShell scripts to get WinGet automatically managed


## 📄 WinGet-Main.vbs

Este script VBS está diseñado para ejecutar un script de PowerShell con privilegios de administrador de forma automática y en segundo plano. Es útil para tareas que requieren elevación sin intervención manual del usuario (más allá del aviso UAC).

### 🔧 ¿Qué hace?

Verifica que exista el script WinGet-Main.ps1 en %ProgramData%\WinGet-extra\.

Comprueba si se está ejecutando con permisos de administrador.

Si no tiene permisos, relanza el script de PowerShell con privilegios elevados (runas).

Si ya tiene permisos, ejecuta el script directamente en segundo plano.


### 📁 Requisitos

Guardar WinGet-Main.ps1 en:
%ProgramData%\WinGet-extra\WinGet-Main.ps1

Ejecutar WinGet-Main.vbs con doble clic o desde línea de comandos.


### 📌 Notas

Utiliza ShellExecute para elevar permisos con UAC.

El archivo temporal admin-test.tmp se usa para comprobar si hay permisos de escritura en %ProgramData%.