# BankMex_Sys_Storage

App de Flutter para BAMX Guadalajara. Las familias ven su despensa, recetas, plan de comidas y perfil. El staff registra cuentas y entregas. El backend es Firebase (Auth, Cloud Firestore y Cloud Functions).

## Configuración inicial

1. Instala Flutter, Node.js 24 (el runtime de la Cloud Function, `functions/package.json`), Java 21 o más reciente (lo piden los emuladores; `java -version` debe funcionar en la terminal) y Firebase CLI (`npm install -g firebase-tools`), y corre `firebase login`.
2. Genera la configuración de Firebase del proyecto `bank-storage-bamx`. Los archivos que crea están en `.gitignore`:

   ```sh
   dart pub global activate flutterfire_cli
   dart pub global run flutterfire_cli:flutterfire configure --project=bank-storage-bamx --platforms=android,ios,web
   ```

   Esto crea `lib/firebase_options.dart`, `android/app/google-services.json` y, para iOS, `ios/Runner/GoogleService-Info.plist`, además de `firebase.json`.

3. Agrega a `firebase.json` la Cloud Function y los emuladores:

   ```json
   "functions": [
     {
       "source": "functions",
       "codebase": "default",
       "ignore": [
         "node_modules",
         ".git",
         "test",
         "firebase-debug.log",
         "firebase-debug.*.log",
         "*.local"
       ]
     }
   ],
   "emulators": {
     "ui": {
       "enabled": true,
       "port": 4000
     },
     "functions": {
       "port": 5001
     },
     "firestore": {
       "port": 8080
     },
     "auth": {
       "port": 9099
     },
     "singleProjectMode": true
   }
   ```

   Si tu `firebase.json` todavía no tiene la sección `firestore`, agrégala también (`"firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" }`): de ahí salen las reglas que carga el emulador y las que se despliegan.

   Crea también `.firebaserc` con `{ "projects": { "default": "bank-storage-bamx" } }`.

4. Instala las dependencias de la Cloud Function (lo único de npm que usa el proyecto; desde la raíz):

   ```sh
   npm --prefix functions install
   ```

5. Para compilar en **Android**, Flutter necesita un JDK que pueda correr la versión de Gradle del proyecto. La versión de Gradle es **una sola para todo el equipo**: la fija `android/gradle/wrapper/gradle-wrapper.properties` (Gradle 9.3.1, la que pide el plugin de Android 9.1.0 de `android/settings.gradle.kts`) y `./gradlew` la descarga igual en todas las computadoras. Lo que cambia en cada computadora es el JDK: Gradle 9 necesita JDK 17 o más reciente.

   ```sh
   flutter doctor -v                         # "Java version" debe ser 17 o más reciente
   flutter config --jdk-dir "<ruta al JDK>"  # solo si no lo es; se guarda en tu computadora, no en el repo
   cd android && ./gradlew --version         # muestra el Gradle y el JDK que se usan
   ```

   Si Android Studio ofrece actualizar o bajar la versión de Gradle o del plugin de Android, no subas ese cambio en un PR de otra cosa: cambia la compilación de todo el equipo. Si hace falta cambiarla, que sea en su propio PR. Compilar para web (Chrome) no usa Gradle, así que ahí no se nota si la versión está mal.

## Correr la app

En **debug** (`flutter run`) la app usa los emuladores de Firebase (Auth 9099, Firestore 8080, Functions 5001) y **no** toca los datos reales.

```sh
# en otra terminal
firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data
node tool/seed_emulators.mjs                               # datos de prueba
flutter run
```

Los datos de los emuladores (cuentas de Auth y documentos de Firestore) se guardan en `exported-dev-data/` al cerrarlos con `Ctrl+C` y se vuelven a cargar al iniciarlos, así no hay que correr el seed cada vez. Si se cierran de golpe (se mata el proceso o se apaga la computadora) no se guarda lo de esa sesión.

- La primera vez la carpeta no existe: los emuladores inician vacíos y se crea al cerrarlos.
- Para empezar de cero, cierra los emuladores y borra `exported-dev-data/`.
- Está en `.gitignore` y **nunca** se sube al repo: incluye las cuentas de Auth del emulador.

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
