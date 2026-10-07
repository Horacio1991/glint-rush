# Google Auth en Android — configuración y prueba manual

Esta fase añade identidad Supabase y perfil público. La partida, el récord y los rivales de demostración siguen siendo locales; no se envían scores y no se habilita ranking online. Si falla la red, la cuenta o el complemento, **JUGAR** continúa disponible.

## Valores que hay que decidir

Antes de exportar, elige un identificador Android definitivo (por ejemplo, un dominio invertido que controles). No hay uno fijado en el proyecto. Usa exactamente el mismo ID en el preset Android de Godot y en cualquier futura publicación. El callback móvil de esta implementación es:

```text
glintrush://auth/callback
```

## 1. Configurar el proveedor Google

1. En Google Cloud Console, selecciona o crea un proyecto de desarrollo y configura la pantalla de consentimiento OAuth para las cuentas de prueba que usarás.
2. Crea un OAuth Client ID de tipo **Web application**. No crees un cliente Android para este flujo de navegador del sistema.
3. En Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs**, permite exactamente `glintrush://auth/callback`. Si la consola exige el comodín de query, permite `glintrush://auth/callback*`.
4. En Supabase Dashboard → **Authentication → Providers → Google**, activa Google y copia el Client ID y Client Secret del cliente Web.
5. En Google Cloud, agrega como **Authorized redirect URI** la URL de callback que muestra el panel del proveedor Google en Supabase. Tiene esta forma: `https://TU_PROJECT_REF.supabase.co/auth/v1/callback`.
6. Guarda el proveedor en Supabase. El Client Secret de Google solo se guarda allí; no lo pongas en Godot, en Android ni en `backend_config.cfg`.

Supabase inicia el authorization code flow con PKCE. El secreto efímero `code_verifier`, el estado anti-CSRF y el refresh token solo se guardan cifrados por el complemento Android. El access token vive en memoria y nunca se escribe en archivos, logs ni preferencias en claro.

Las huellas SHA-1/SHA-256 **no son necesarias** para el cliente OAuth Web de este flujo: el usuario autoriza en navegador y Google vuelve primero a Supabase. Si más adelante se cambia a Google Sign-In nativo, se pueden consultar las huellas de la firma debug con `keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android` en PowerShell, y la firma configurada en Android Studio con `gradlew signingReport`. Para Play se debe registrar también la huella del certificado release real.

## 2. Configurar el proyecto local

1. Abre el ZIP y copia `backend_config.example.cfg` a `backend_config.cfg`.
2. Completa `url` con la Project URL del proyecto Supabase DEV y `public_key` con la publishable key (o la anon key legacy). El archivo real está ignorado por Git y no debe compartirse. No uses `service_role`, una secret key, contraseña de base o secreto Google.
3. En el export preset Android de Godot, configura el identificador de paquete que elegiste. No se requiere SHA-1/SHA-256 de Android para esta configuración de OAuth Web mediante navegador; esas huellas se obtienen si en una fase futura se adopta un cliente Android nativo de Google Sign-In, que este flujo no utiliza.
4. En Godot, revisa **Project → Project Settings → Plugins** y habilita **GLINT RUSH Android Auth**.
5. Instala **Project → Install Android Build Template** y agrega un preset Android en **Project → Export**. Activa **Use Gradle Build**.

## 3. Compilar e incluir el puente Android

El ZIP trae el código fuente del plugin v2. El AAR debe compilarse una vez en un equipo con JDK 17, Android SDK, Gradle 8.7 y conexión al repositorio Maven de Godot. El plugin agrega permiso `INTERNET` (no solicita permiso durante ejecución). Desde `android/auth-plugin`:

```powershell
gradle copyReleaseAar
```

Esto crea `addons/glintrush_auth/bin/glintrush-auth.aar`. Abre/recarga el proyecto en Godot después de generarlo. La extensión de exportación agrega ese AAR y el filtro del callback `glintrush://auth/callback` al manifest Android. El export preset debe usar Gradle.

Para un APK local, exporta en modo debug. Instálalo por USB con `adb install -r .\glint-rush-debug.apk` o transfiérelo al teléfono e instala el APK. Una publicación requiere firma release propia; el proyecto no contiene un keystore.

## 4. Recorrido de prueba

1. Abre GLINT RUSH en Android y pulsa **ENTRAR CON GOOGLE**.
2. Completa la autorización en el navegador del sistema y acepta la vuelta a GLINT RUSH.
3. En portada debe aparecer el nombre público y handle generados. Cierra y vuelve a abrir la app: si se guardó la sesión, debe restaurarse.
4. Comprueba en Supabase Dashboard → **Authentication → Users** que existe el usuario.
5. En Supabase SQL Editor de DEV, comprueba solo los campos públicos del perfil:

   ```sql
   select id, handle, display_name, avatar_key, created_at
   from public.profiles
   order by created_at desc
   limit 5;
   ```

   Debe existir una fila cuyo `id` coincida con el usuario de Auth. `profiles` no guarda email.
6. Pulsa **SALIR**, vuelve a iniciar sesión y luego **JUGAR**: login/logout no deben cambiar tablero, cuenta regresiva, score o reloj.
7. Repite con cancelación del navegador, modo avión o sin el plugin compilado: el error debe quedar en la portada y **JUGAR** local debe funcionar.

## 5. Migración y pruebas

La migración nueva es `supabase/migrations/20261005140000_auth_profiles.sql`. Añade índice único de handle, trigger idempotente en `auth.users`, perfil sin email y RPC autenticada de `last_seen` limitada a una escritura cada 15 minutos. No toca la migración fundacional ni añade `start_match`, `submit_match`, tablas de score modificables o ranking online.

Desde la raíz, en una instancia local Supabase:

```powershell
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
```

En Godot, ejecuta `godot --headless --path . --script res://tests/smoke_test.gd`. Las pruebas OAuth locales cubren el formato PKCE, URL, parser de callback, rechazo de tokens implícitos y bloqueo de red bajo `GLINT_RUSH_TEST`; no necesitan una cuenta Google real. La autorización y vuelta por deep link requieren prueba manual en Android.

## Problemas comunes

- **El botón dice que falta el complemento:** compila el AAR, habilita el plugin editor y vuelve a importar el proyecto.
- **Google vuelve a una página de error:** revisa que el Authorized redirect URI de Google sea el callback Supabase, y que el proveedor esté habilitado.
- **Supabase muestra redirect no permitido:** confirma `glintrush://auth/callback` en URL Configuration y que el `redirect_to` conserva el mismo esquema, host y path.
- **Se autoriza Google, pero no vuelve a la app:** confirma el paquete Android elegido y vuelve a exportar con Gradle/plugin activo; consulta `adb logcat` para ver el intent filter fusionado.
- **Login funciona, pero no aparece perfil:** confirma que ambas migraciones se aplicaron en DEV y revisa el error de base en Supabase Logs. No insertes perfiles manualmente desde el cliente.
- **La sesión no persiste al reiniciar:** verifica que Android permita almacenamiento de la app y que el AAR use Android Keystore; en caso de error, el juego debe seguir con sesión solo en memoria/local.

## iOS y seguridad de publicación

iOS queda contemplado en la capa GDScript, pero no está implementado en esta fase. Hace falta un puente nativo iOS equivalente para apertura del navegador, Universal Links/custom URL scheme y Keychain. Antes de publicar, configura el ID Android final, URI de retorno, dominios/pantalla de consentimiento Google, política de privacidad y firma release. No uses credenciales reales de jugadores en smoke tests.
