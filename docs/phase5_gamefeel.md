# GLINT RUSH · Fase 5 — game feel, input y UX

## Resumen

Se conserva la escena `scenes/main.tscn` y la implementación activa `scripts/game.gd`. No se sustituyeron el tablero, el sistema SPEED/CASCADE, la cuenta atrás, Final Blast ni la autenticación.

## Input de arrastre

`_gui_input()` recibe `InputEventScreenDrag` en Android y `InputEventMouseMotion` mientras el botón izquierdo está presionado en PC. `_drag_direction()` aplica un umbral del 22% del tamaño de una casilla y escoge el eje dominante; el signo determina el vecino. `pointer_swap_started` bloquea repeticiones durante el mismo gesto. Antes del umbral, la gema acompaña una fracción del desplazamiento del dedo. Se mantiene además el control de toque y selección de dos gemas adyacentes. Un gesto que empieza fuera del tablero no produce swaps.

## Resolver de matches y especiales

### Comportamiento anterior

`_find_groups()` agrupa gemas conectadas del mismo color. `_special_for_group()` clasifica una línea de cinco como prisma, T/L como cruz, cuatro horizontal/vertical como especial de línea y elige una celda superviviente. `_resolve_board()` deja fuera de la eliminación la celda elegida; las demás celdas del match se eliminan, las especiales alcanzadas se expanden mediante `_collect_special_effects()` con deduplicación, luego ocurre gravedad/refill y se repite para las cascadas. Las combinaciones de prisma (normal, especial transformable y pareja) siguen entrando por sus rutas dedicadas.

El hueco era que la especial antigua colocada en la celda superviviente no entraba en la lista de activación. Al asignar la nueva especial antes de calcular/consumir los efectos, también se podía sustituir su tipo.

### Cambio aplicado

- La celda de creación prefiere el movimiento manual si es una gema normal; en su defecto elige una gema normal del grupo.
- Toda especial antigua que participa en el grupo se agrega como semilla de activación, aunque esté en la celda que originalmente habría sobrevivido.
- El efecto viejo se resuelve y se deduplica en la misma cola que las otras reacciones. La nueva especial se escribe después del paso de limpieza/gravedad. Si todas las celdas del grupo ya eran especiales, la celda de creación se vuelve a cargar después de consumirse la pieza antigua.
- El test añadido comprueba que un especial de línea existente se consuma y que el match de cuatro conserve su nueva línea.

Las reglas existentes se mantienen: 3 normal; 4 línea horizontal/vertical; T/L cruz; 5 prisma; prisma+normal limpia color; prisma+prisma limpia todo; prisma+especial convierte las gemas normales del color en especiales compatibles; especiales alcanzados reaccionan una sola vez; cascadas siguen resolviéndose; Final Blast drena las especiales restantes de forma determinista. `bomb` permanece soportada por el colector para compatibilidad, aunque la T/L actual crea `cross`.

## Reinicio, salida y Auth

REINICIAR/SALIR muestran una confirmación. Se desactiva `application/config/quit_on_go_back` y el cierre automático de la ventana para que Android Back y la solicitud de cierre de escritorio pasen por la confirmación. Atrás/Escape primero cierra el diálogo; fuera del diálogo abre confirmación de salida. Reiniciar incrementa `round_generation`, detiene el tween del swap y los reproductores de efectos, limpia el estado visual/tablero temporal y restablece reloj, SPEED, cascadas, especiales y locks antes de entrar al countdown de una nueva ronda. Las rutinas asíncronas comprueban la generación al volver de cada espera y no pueden continuar mutando la ronda nueva. El logout sigue llamando a `AuthService.logout()`; solo se cambió su presentación y quedó centrado. Las llamadas del bridge Android siguen usando `has_java_method()`.

## Archivos modificados

- `project.godot`: desactiva el cierre automático mediante Atrás para permitir la confirmación.
- `scripts/game.gd`: drag, protección de gesto, resolución de especial+creación, invalidación de resolución/tween/audio diferidos, reiniciar/salir, confirmaciones y logout centrado.
- `scripts/services/auth_service.gd`: se retiraron cinco `print()` de diagnóstico temporal; se conservaron warnings y el uso de `has_java_method()`.
- `tests/smoke_test.gd`: umbral/dirección drag, coexistencia de activación especial y creación nueva, cancelación de una resolución por reinicio.
- `README.md`: controles, opciones y guía de Fase 5.
- `docs/phase5_gamefeel.md`: registro técnico de esta fase.

## Validación

El smoke test fue ampliado, pero **NO EJECUTADO** aquí: no se encontró `godot` ni `godot4` en el entorno. Por el mismo motivo no se pudo comprobar apertura/parser de escenas desde el motor. El código mantiene las comprobaciones `has_java_method()`; la prueba de OAuth/gesto Atrás/dispositivo Android es **NO EJECUTADA — requiere dispositivo Android**.

Pruebas manuales sugeridas en el celular:

1. Hacer swipe corto horizontal y vertical; confirmar un solo intercambio por gesto y probar un swipe que no produzca match.
2. Arrastrar varias casillas y confirmar que solo intenta la vecina dominante.
3. Crear una línea y detonar una especial existente dentro de un match que genere otra; revisar efecto, puntaje y supervivencia de la nueva pieza. Repetir con T/L y cascadas.
4. Abrir REINICIAR, cancelar y confirmar; repetir varias veces durante caída, especial y Final Blast.
5. Abrir SALIR, usar Atrás para cancelar y luego confirmar salida desde el botón.
6. Comprobar SALIR DE LA CUENTA visualmente y verificar que no cambió el flujo de login/refresh.

## Contenido excluido del ZIP

Se excluyeron `backend_config.cfg`, `android/auth-plugin/local.properties`, `supabase/.temp/`, `.idea/` y `tmp-aar/`. Contienen configuración local, rutas/estado de herramientas o artefactos derivados; el proyecto usa el archivo de ejemplo de backend y el AAR/plugin fuente ya incluidos. No se modificaron migraciones.
