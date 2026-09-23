# BankMex_Sys_Storage

App de Flutter para BAMX Guadalajara. Las familias ven su despensa, recetas, plan de comidas y perfil. El staff registra cuentas y entregas. El backend es Firebase (Auth, Cloud Firestore y Cloud Functions).

## Configuración inicial

1. Instala Flutter, Node.js (22 o más reciente), Java 21 o más reciente (lo piden los emuladores; `java -version` debe funcionar en la terminal) y Firebase CLI (`npm install -g firebase-tools`), y corre `firebase login`.
2. Genera la configuración de Firebase del proyecto `bank-storage-bamx`. Los archivos que crea están en `.gitignore`:

   ```sh
   dart pub global activate flutterfire_cli
   dart pub global run flutterfire_cli:flutterfire configure --project=bank-storage-bamx --platforms=android,web
   ```

   Esto crea `lib/firebase_options.dart`, `android/app/google-services.json` y `firebase.json`.

3. Agrega a `firebase.json` las reglas, la Cloud Function y los emuladores:

   ```json
   "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
   "functions": [
     {
       "source": "functions",
       "codebase": "default",
       "ignore": ["node_modules", ".git", "firebase-debug.log", "firebase-debug.*.log", "*.local"]
     }
   ],
   "emulators": {
     "auth": { "port": 9099 },
     "firestore": { "port": 8080 },
     "functions": { "port": 5001 },
     "ui": { "enabled": true, "port": 4000 },
     "singleProjectMode": true
   }
   ```

   Crea también `.firebaserc` con `{ "projects": { "default": "bank-storage-bamx" } }`.

4. Instala las dependencias de la Cloud Function (desde la raíz del proyecto):

   ```sh
   npm --prefix functions install
   ```

## Correr la app

En **debug** (`flutter run`) la app usa los emuladores de Firebase (Auth 9099, Firestore 8080, Functions 5001) y **no** toca los datos reales.

```sh
firebase emulators:start --only auth,firestore,functions   # en otra terminal
node tool/seed_emulators.mjs                               # datos de prueba
flutter run
```

Cuentas de prueba del seed (contraseña `bamx1234`):

- Staff: `staff@bamx.test`
- Familia: `familia.ramirez@bamx.test`
- Solicitud de staff pendiente de aprobar: `solicitud.staff@bamx.test`

En **release** (`flutter run --release`) la app usa el proyecto real `bank-storage-bamx`. Para que funcione, la Cloud Function y las reglas deben estar desplegadas. Conviene desplegar primero la función (requiere el plan Blaze del proyecto) y revisar que `onDeliveryWritten` aparezca en `northamerica-south1`:

```sh
firebase deploy --only functions
firebase deploy --only firestore:rules
```

Si una entrega queda como entregada mientras la función no está desplegada, sus productos no llegan a la despensa y la app ya no puede volver a escribir esa entrega. Para recuperarla, después de desplegar la función edita cualquier campo de la entrega desde la consola de Firebase: la función se vuelve a disparar y la surte, porque no tiene `pantryStockedAt`.

## Despensa y entregas

Ningún cliente, incluido el staff, crea productos en `families/{familyId}/pantryItems`; las reglas lo rechazan. El flujo es:

1. El staff registra la entrega en `deliveries` como **entregada**, o la registra **programada** y después la marca como entregada.
2. La Cloud Function `onDeliveryWritten` (`functions/index.js`) detecta que la entrega quedó como entregada. En una transacción crea un `PantryItem` por producto, menos los que ya caducaron, y marca la entrega con `pantryStockedAt`. La marca evita que un reintento duplique productos.
3. La familia ve los productos en su despensa. Al registrar consumo solo puede bajar la cantidad de un producto, o borrarlo cuando se acaba.

Una entrega **programada** también se puede **reasignar** a otra familia. En un solo batch, la original queda como `reassigned` (con `reassignedTo`) y se crea una entrega nueva programada para la otra familia (con `reassignedFrom`), con la misma fecha, despensas y productos.

Los integrantes de la familia se guardan en la subcolección `families/{familyId}/members`, con `MemberRepository` y sus propias reglas (`validMember`).

## Cuentas

- **Familias:** las crea el staff desde "Registrar cuenta", en el panel de staff.
- **Staff:** las crea otro staff desde "Registrar cuenta", o la persona las solicita desde "¿Eres personal de BAMX? Regístrate" en el inicio de sesión. La solicitud se guarda en `staffRequests/{uid}` y la persona no puede entrar hasta que un staff la aprueba desde "Solicitudes de staff". Al aprobarla se crea su perfil `users/{uid}` con rol staff.

## Pruebas

Todas las pruebas se corren con Flutter:

```sh
flutter analyze
flutter test                                    # unitarias y de widgets (no necesitan emuladores)
flutter test test_emulator                      # reglas de seguridad y Cloud Function; requiere los emuladores corriendo
flutter test integration_test -d <emulador>     # de punta a punta; requiere emuladores (con functions) y correr el seed antes
```

`test_emulator/` habla con el emulador de Firestore por su API REST (`test_emulator/support/emulator.dart`): las pruebas de reglas usan proyectos de prueba aparte, y la de la Cloud Function usa el proyecto real del emulador, con ids propios que limpia al terminar.

Para guardar capturas de la prueba de punta a punta en `build/e2e_screenshots`:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_flow_test.dart -d <emulador> --dart-define=E2E_SCREENSHOTS=true
```

## Cómo está organizado

- `lib/data`: modelos y repositorios de Firestore (familias, integrantes, despensa, entregas, usuarios y autenticación).
- `lib/ui`: tema, widgets compartidos y pantallas (`screens/`) de la familia y del staff.
- `functions`: Cloud Function que agrega a la despensa los productos de una entrega confirmada.
- `test_emulator`: pruebas de las reglas y de la Cloud Function contra los emuladores.
- `firestore.rules`: reglas de seguridad.
  - Solo el staff crea perfiles, familias y entregas. Una solicitud de staff solo se convierte en cuenta cuando otro staff la aprueba.
  - Solo la Cloud Function crea productos en la despensa.
  - Cada familia solo accede a lo suyo.
  - Una entrega programada cambia de estado una sola vez: a entregada, cancelada o reasignada.
