# Supabase de desarrollo — GLINT RUSH

Esta carpeta contiene la fundación online y las migraciones de autenticación y Phase 6. Reutiliza `matches`, `weekly_scores`, `seasons` y `profiles` para almacenar scores reclamados por usuarios autenticados y exponer un ranking semanal por mejor puntuación. El cliente es offline-first y el score todavía no tiene verificación anti-cheat server-side.

## Requisitos

- Docker Desktop iniciado para la pila local administrada por Supabase CLI. No se agrega Dockerfile ni servidor propio a GLINT RUSH.
- Node.js/npm si se usa `npx` para ejecutar Supabase CLI.
- Godot 4.7 o superior para mantener compatibilidad con el complemento Android de Auth; el backend puede prepararse independientemente.

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

Los tests SQL usan pgTAP y comprueban tablas, RLS, grants, RPC de temporada, envío idempotente, mejor score semanal, ranking y usuario fuera del Top. Los casos manuales de aislamiento A/B se detallan en `../docs/supabase_rls_manual_test.md`.

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

La clave es pública, pero aun así no pegarla en issues, capturas ni conversaciones públicas. En Android, si se empaqueta `backend_config.cfg`, la URL/clave pública viajan dentro del APK y deben considerarse visibles. No son secretos. Con cuenta autenticada, el juego envía el score al terminar y consulta el ranking al abrirlo. Sin sesión o sin conexión, la partida local sigue funcionando y no se conserva una cola offline.

## Revisar migraciones

Migraciones actuales:

- `migrations/20261005000000_online_foundation.sql`
- `migrations/20261005140000_auth_profiles.sql`
- `migrations/20261007140000_weekly_competitive_scores.sql`

La fundación incluye perfiles, semanas ISO, sesiones server-side, historial, mejor score semanal, podios, índices, grants y RLS. Phase 6 agrega RPCs autenticadas `submit_match_score()` y `get_weekly_leaderboard()`. La primera deriva el dueño de `auth.uid()`, registra `pending_review`, mantiene idempotencia y actualiza el mejor score; la segunda devuelve handles públicos y score, sin emails. Los clientes no obtienen grants directos de escritura. `session_id` queda nullable para estos scores de desarrollo sin ticket de servidor; un ticket genuino sigue soportado. Las seasons pasadas y sus resultados se conservan.

Para empezar de cero y aplicar migraciones, usar `supabase db reset`. Para inspección manual desde Studio local, abrir SQL Editor. No pegar cambios manuales en un Supabase remoto y olvidarse de registrarlos en una migración.

## Autoridad temporal

La función `get_current_season()` obtiene hora PostgreSQL y calcula lunes 00:00 UTC a lunes siguiente 00:00 UTC. Formatea año/semana ISO (`IYYY`/`IW`) y crea la fila con `ON CONFLICT DO NOTHING`. El ranking de la semana nueva se inicia con otra season; no borra filas previas. No hay job de premios/cierre semanal.

## Autoridad del score

Los resultados Phase 6 son client-authoritative para pruebas. Un usuario autenticado solo puede crear filas bajo su propio `auth.uid()`, pero puede modificar el cliente y falsificar el número enviado. Las filas quedan `pending_review`; no presentar este sistema como anti-cheat ni habilitarlo para competencia pública sin tickets, replay/verificación server-side y leaderboard que filtre solo scores verificados. Ver [`../docs/phase6_competitive.md`](../docs/phase6_competitive.md).
