// Apoyo para probar firestore.rules desde Dart contra el emulador de
// Firestore, con la API REST y tokens de prueba (el emulador no verifica la
// firma, igual que hace la herramienta oficial de Firebase).
//
// Se usa un proyecto aparte (demo-bamx-rules) para no tocar los datos de
// desarrollo del emulador.
import 'dart:convert';
import 'dart:io';

final _firestoreHost =
    Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';

/// Proyecto del emulador donde escribe este archivo de pruebas. Cada archivo
/// usa el suyo (useProject en su main) para que varios puedan correr a la vez
/// sin borrarse los datos entre ellos. Las reglas son las mismas para todos.
String _project = 'demo-bamx-rules';

void useProject(String name) => _project = name;

String get _documents =>
    'http://$_firestoreHost/v1/projects/$_project/databases/(default)/documents';

/// Códigos que regresa el emulador: 200 y 404 (no existe) pasaron las reglas;
/// 403 es PERMISSION_DENIED.
const _ok = 200;
const _notFound = 404;
const _denied = 403;

// ---------------------------------------------------------------------------
// Valores tipados de la API REST
// ---------------------------------------------------------------------------

Map<String, Object?> str(String value) => {'stringValue': value};
Map<String, Object?> integer(int value) => {'integerValue': '$value'};
Map<String, Object?> number(num value) => {'doubleValue': value};
Map<String, Object?> boolean(bool value) => {'booleanValue': value};
Map<String, Object?> ts(DateTime value) => {
  'timestampValue': value.toUtc().toIso8601String(),
};
Map<String, Object?> nul() => {'nullValue': null};
Map<String, Object?> arr(List<Map<String, Object?>> values) => {
  'arrayValue': values.isEmpty ? <String, Object?>{} : {'values': values},
};
Map<String, Object?> mapValue(Map<String, Map<String, Object?>> fields) => {
  'mapValue': {'fields': fields},
};

/// Marca un campo para borrarlo en un update (va en la máscara, no en los
/// campos), como FieldValue.delete().
const deleteField = _DeleteField();

class _DeleteField {
  const _DeleteField();
}

/// FieldValue.increment(value).
class Increment {
  const Increment(this.value);

  final num value;
}

/// FieldValue.serverTimestamp().
class ServerTimestamp {
  const ServerTimestamp();
}

const serverTimestamp = ServerTimestamp();

// ---------------------------------------------------------------------------
// Cliente
// ---------------------------------------------------------------------------

/// Una sesión contra el emulador: el staff, una familia, alguien sin cuenta o
/// el administrador (que se salta las reglas, para preparar los datos).
class Db {
  Db._(this._authorization);

  /// Escribe y lee sin pasar por las reglas (para preparar los datos).
  factory Db.admin() => Db._('Bearer owner');

  /// Sesión iniciada con ese uid. El emulador no verifica la firma del token.
  factory Db.user(String uid, {String? email}) =>
      Db._('Bearer ${_token(uid, email: email)}');

  /// Sin sesión.
  factory Db.anonymous() => Db._(null);

  final String? _authorization;

  /// Crea o reemplaza el documento completo (como setDoc).
  Future<int> setDoc(String path, Map<String, Map<String, Object?>> fields) =>
      commit([
        {
          'update': {'name': _name(path), 'fields': fields},
        },
      ]);

  /// Cambia solo los campos indicados; falla si el documento no existe (como
  /// updateDoc). Acepta [Increment], [ServerTimestamp] y [deleteField].
  Future<int> updateDoc(String path, Map<String, Object?> changes) =>
      commit([updateWrite(path, changes)]);

  /// Crea un documento con id automático en la colección (como addDoc).
  Future<int> addDoc(
    String collectionPath,
    Map<String, Map<String, Object?>> fields,
  ) => _send('POST', '$_documents/$collectionPath', {'fields': fields});

  Future<int> deleteDoc(String path) => commit([deleteWrite(path)]);

  Future<int> getDoc(String path) => _send('GET', '$_documents/$path');

  /// Lista una colección (como getDocs(collection(...))). [parent] vacío es la
  /// raíz; [where] filtra por igualdad.
  Future<int> listDocs(
    String collectionId, {
    String parent = '',
    (String, Map<String, Object?>)? where,
    String? orderBy,
    int? limit,
  }) {
    final query = <String, Object?>{
      'from': [
        {'collectionId': collectionId},
      ],
      if (where != null)
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': where.$1},
            'op': 'EQUAL',
            'value': where.$2,
          },
        },
      if (orderBy != null)
        'orderBy': [
          {
            'field': {'fieldPath': orderBy},
            'direction': 'DESCENDING',
          },
        ],
      'limit': ?limit,
    };
    final url = parent.isEmpty
        ? '$_documents:runQuery'
        : '$_documents/$parent:runQuery';
    return _send('POST', url, {'structuredQuery': query});
  }

  /// Varias escrituras en un solo batch, como writeBatch: si las reglas
  /// rechazan una, se rechaza todo.
  Future<int> commit(List<Map<String, Object?>> writes) =>
      _send('POST', '$_documents:commit', {'writes': writes});

  Future<int> _send(String method, String url, [Object? body]) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      request.headers.contentType = ContentType.json;
      if (_authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, _authorization);
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close();
    }
  }
}

/// Escritura de update para usar dentro de [Db.commit].
Map<String, Object?> updateWrite(String path, Map<String, Object?> changes) {
  final fields = <String, Map<String, Object?>>{};
  final mask = <String>[];
  final transforms = <Map<String, Object?>>[];

  changes.forEach((field, value) {
    switch (value) {
      case Increment(:final value):
        transforms.add({
          'fieldPath': field,
          'increment': {'doubleValue': value},
        });
      case ServerTimestamp():
        transforms.add({
          'fieldPath': field,
          'setToServerValue': 'REQUEST_TIME',
        });
      case _DeleteField():
        mask.add(field);
      case final Map<String, Object?> typed:
        fields[field] = typed;
        mask.add(field);
      default:
        throw ArgumentError('Valor no soportado para $field: $value');
    }
  });

  return {
    'update': {'name': _name(path), if (fields.isNotEmpty) 'fields': fields},
    'updateMask': {'fieldPaths': mask},
    if (transforms.isNotEmpty) 'updateTransforms': transforms,
    'currentDocument': {'exists': true},
  };
}

/// Escritura de set (crear o reemplazar) para usar dentro de [Db.commit].
Map<String, Object?> setWrite(
  String path,
  Map<String, Map<String, Object?>> fields,
) => {
  'update': {'name': _name(path), 'fields': fields},
};

/// Escritura de borrado para usar dentro de [Db.commit].
Map<String, Object?> deleteWrite(String path) => {'delete': _name(path)};

String _name(String path) =>
    'projects/$_project/databases/(default)/documents/$path';

/// Lee un documento como administrador; regresa sus campos o null si no
/// existe (para revisar lo que dejó la Cloud Function).
Future<Map<String, Object?>?> adminDoc(String path) async {
  final body = await _adminGet('$_documents/$path');
  if (body == null) return null;
  return (body['fields'] as Map<String, Object?>?) ?? <String, Object?>{};
}

/// Documentos de una colección, como administrador, con su id y sus campos.
Future<List<({String id, Map<String, Object?> fields})>> adminDocs(
  String collectionPath,
) async {
  final body = await _adminGet('$_documents/$collectionPath?pageSize=300');
  final documents = (body?['documents'] as List<Object?>?) ?? const [];
  return [
    for (final document in documents.cast<Map<String, Object?>>())
      (
        id: (document['name'] as String).split('/').last,
        fields:
            (document['fields'] as Map<String, Object?>?) ?? <String, Object?>{},
      ),
  ];
}

/// El texto de un campo leído con [adminDoc] ('stringValue', 'integerValue'…).
Object? fieldValue(Map<String, Object?>? fields, String name) {
  final value = fields?[name] as Map<String, Object?>?;
  if (value == null) return null;
  final entry = value.entries.first;
  return switch (entry.key) {
    'integerValue' => int.parse(entry.value as String),
    'doubleValue' => (entry.value as num).toDouble(),
    _ => entry.value,
  };
}

Future<Map<String, Object?>?> _adminGet(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode == _notFound) return null;
    if (response.statusCode != _ok) {
      throw StateError('No se pudo leer $url (HTTP ${response.statusCode})');
    }
    return jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// Borra todos los datos del proyecto de pruebas entre casos.
Future<void> clearFirestore() async {
  final client = HttpClient();
  try {
    final request = await client.deleteUrl(
      Uri.parse(
        'http://$_firestoreHost/emulator/v1/projects/$_project/databases/(default)/documents',
      ),
    );
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != _ok) {
      throw StateError(
        'No se pudieron borrar los datos del emulador '
        '(HTTP ${response.statusCode}).',
      );
    }
  } finally {
    client.close();
  }
}

/// Falla con un mensaje claro si el emulador de Firestore no está corriendo y
/// carga en este proyecto el firestore.rules del repo: para un proyecto que no
/// es el suyo, el emulador se queda con las reglas que tenía al arrancar.
Future<void> requireEmulator() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(Uri.parse('http://$_firestoreHost/'));
    final response = await request.close();
    await response.drain<void>();
  } catch (_) {
    throw StateError(
      'No se encontró el emulador de Firestore en $_firestoreHost.\n'
      'Inícialo con: firebase emulators:start --only auth,firestore,functions --import=exported-dev-data --export-on-exit=exported-dev-data',
    );
  } finally {
    client.close();
  }
  await _loadRules();
}

Future<void> _loadRules() async {
  final rules = _rulesFile();
  final client = HttpClient();
  try {
    final request = await client.putUrl(
      Uri.parse(
        'http://$_firestoreHost/emulator/v1/projects/$_project:securityRules',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'rules': {
          'files': [
            {'name': 'firestore.rules', 'content': rules.readAsStringSync()},
          ],
        },
      }),
    );
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != _ok) {
      throw StateError(
        'No se pudieron cargar las reglas en el emulador '
        '(HTTP ${response.statusCode}): $text',
      );
    }
  } finally {
    client.close();
  }
}

/// firestore.rules de la raíz del proyecto (las pruebas pueden correrse desde
/// la raíz o desde una subcarpeta).
File _rulesFile() {
  var directory = Directory.current;
  for (var i = 0; i < 5; i++) {
    final file = File('${directory.path}${Platform.pathSeparator}firestore.rules');
    if (file.existsSync()) return file;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('No se encontró firestore.rules desde ${Directory.current}');
}

/// Token sin firmar con ese uid; el emulador lo acepta tal cual.
String _token(String uid, {String? email}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = {'alg': 'none', 'kid': '', 'typ': 'JWT'};
  final payload = {
    'iss': 'https://securetoken.google.com/$_project',
    'aud': _project,
    'iat': now,
    'exp': now + 3600,
    'auth_time': now,
    'sub': uid,
    'user_id': uid,
    'email': ?email,
    'email_verified': false,
    'firebase': {
      'identities': <String, Object?>{},
      'sign_in_provider': 'password',
    },
  };
  String encode(Map<String, Object?> part) =>
      base64Url.encode(utf8.encode(jsonEncode(part))).replaceAll('=', '');
  return '${encode(header)}.${encode(payload)}.';
}

// ---------------------------------------------------------------------------
// Aserciones
// ---------------------------------------------------------------------------

/// La operación pasó las reglas (200, o 404 si el documento no existe).
Future<void> assertAllowed(Future<int> operation) async {
  final status = await operation;
  if (status != _ok && status != _notFound) {
    throw StateError('Se esperaba que las reglas lo permitieran, HTTP $status');
  }
}

/// Las reglas la rechazaron (403).
Future<void> assertDenied(Future<int> operation) async {
  final status = await operation;
  if (status != _denied) {
    throw StateError('Se esperaba PERMISSION_DENIED (403), HTTP $status');
  }
}
