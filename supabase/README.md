# Supabase de desarrollo — GLINT RUSH

Esta carpeta contiene una migración ejecutable de la **fundación** online y un test pgTAP de grants/esquema. No incluye el backend de scores: todavía no existe `start_match`, `submit_match`, Google Auth, perfil automático, amigos operativos, cierre semanal ni ranking online.

## Requisitos

- Docker Desktop iniciado para la pila local administrada por Supabase CLI. No se agrega Dockerfile ni servidor propio a GLINT RUSH.
- Node.js/npm si se usa `npx` para ejecutar Supabase CLI.
- Godot 4.3 o superior para abrir el juego; el backend puede prepararse independientemente.

## Ejecutar el entorno local

Desde la carpeta raíz del proyecto (`glint-rush`):

```powershell
npx --yes supabase@latest --version
npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
npx --yes supabase@latest status
```

`db reset` recrea la base local y aplica todas las migraciones en orden. No usar este comando contra producción. El stack local muestra las URLs y claves efímeras en `status`; el Studio local normalmente abre en `http://127.0.0.1:54323`.

Para apagar el stack:

```powershell
npx --yes supabase@latest stop
```

El test SQL usa pgTAP y comprueba existencia de tablas, RLS, permisos de lectura, ausencia de grants de escritura, acceso a `get_current_season()` y el índice/constraints principales. Los casos de filas entre usuarios A/B se detallan en `../docs/supabase_rls_manual_test.md`.

## Crear un proyecto de desarrollo en Dashboard

1. En Supabase Dashboard, crea un proyecto separado para desarrollo y guarda la contraseña de base de datos en un gestor de contraseñas.
2. No habilites Google OAuth todavía.
3. En **Project Settings → API Keys** (el rótulo puede variar), copia la **Project URL** y la clave **publishable**; en proyectos que aún muestran las claves legacy, la clave de cliente es `anon`.
4. No copies `secret` ni `service_role` a GLINT RUSH. La contraseña de base tampoco va en el juego.
5. Las migraciones se aplican primero y se prueban en el stack local. Para un proyecto remoto de desarrollo, después de revisar localmente:

```powershell
npx --yes supabase@latest login
npx --yes supabase@latest link --project-ref TU_PROJECT_REF
npx --yes supabase@latest db push
```

La CLI pedirá la contraseña de base de datos de forma interactiva. No la pongas como argumento en comandos guardados ni la compartas. `db push` aplica migraciones al proyecto remoto enlazado: verificar cuidadosamente el project ref antes de confirmarlo. No enlazar ni empujar a producción durante las pruebas iniciales.

## Configuración para Godot

El proyecto incluye `backend_config.example.cfg`, sin credenciales reales. En PowerShell, opcionalmente crear el archivo local:

```powershell
Copy-Item backend_config.example.cfg backend_config.cfg
```

Completar solo:

```ini
[supabase]
url="https://TU_PROJECT_REF.supabase.co"
public_key="TU_PUBLISHABLE_O_ANON_KEY"
```

`backend_config.cfg` está en `.gitignore`. Para desarrollo en escritorio también se pueden usar variables en la misma consola desde la que se inicia Godot:

```powershell
$env:SUPABASE_URL = "https://TU_PROJECT_REF.supabase.co"
$env:SUPABASE_PUBLIC_KEY = "TU_PUBLISHABLE_O_ANON_KEY"
```

La clave es pública, pero aun así no pegarla en issues, capturas ni conversaciones públicas. En Android, si se empaqueta `backend_config.cfg`, la URL/clave pública viajan dentro del APK y deben considerarse visibles. No son secretos. En esta fase el juego no inicia sesión ni llama a endpoints durante una partida; tener la configuración no activa un ranking ni cambia el modo local.

## Revisar migraciones

Migración única actual:

- `migrations/20261005000000_online_foundation.sql`

Incluye perfiles, relaciones, semanas ISO, sesiones, historial, best semanal, podios, constraints, índices, RLS, grants mínimos y RPC autenticada `get_current_season()`. No acepta ni persiste puntuaciones enviadas por el cliente.

Para empezar de cero y aplicar migraciones, usar `supabase db reset`. Para inspección manual desde Studio local, abrir SQL Editor. No pegar cambios manuales en un Supabase remoto y olvidarse de registrarlos en una migración.

## Autoridad temporal

La función pública `get_current_season()` obtiene hora de PostgreSQL y calcula lunes 00:00 UTC a lunes siguiente 00:00 UTC. Formatea el año ISO (`IYYY`) y la semana (`IW`), y crea la fila con `ON CONFLICT DO NOTHING`. No hay job de cierre ni cambios de estado automáticos en esta fase.
