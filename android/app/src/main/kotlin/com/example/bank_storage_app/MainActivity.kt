package com.example.bank_storage_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // MASVS-PLATFORM-3: Recientes, las capturas de pantalla y las
        // grabaciones no muestran los datos de las familias. Toda la app se
        // dibuja en esta ventana, así que la bandera cubre todas las pantallas.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
