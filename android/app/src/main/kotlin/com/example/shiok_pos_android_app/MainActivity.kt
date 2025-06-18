package com.example.shiok_pos_android_app

import android.view.View
import android.widget.ImageView
import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class CustomerDisplay(context: Context, display: Display) : Presentation(context, display) {
    private lateinit var orderItemsList: ListView
    private lateinit var orderSubtotal: TextView
    private lateinit var orderTax: TextView
    private lateinit var orderTotal: TextView
    private lateinit var splashView: View
    private lateinit var orderDetailsContainer: View
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.customer_screen)

        orderItemsList = findViewById(R.id.orderItemsList)
        orderSubtotal = findViewById(R.id.orderSubtotal)
        orderTax = findViewById(R.id.orderTax)
        orderTotal = findViewById(R.id.orderTotal)
        splashView = findViewById(R.id.defaultSplashView)
        orderDetailsContainer = findViewById(R.id.orderDetailsContainer)
    }

    fun updateOrderDetails(items: List<Map<String, Any>>, subtotal: Double, tax: Double, total: Double) {
        handler.post {
            splashView.visibility = View.GONE
            orderDetailsContainer.visibility = View.VISIBLE

            val adapter = ArrayAdapter(
                context,
                android.R.layout.simple_list_item_1,
                items.map { item ->
                    val name = item["name"]?.toString() ?: "Unnamed"
                    val price = when (val p = item["price"]) {
                        is Double -> p
                        is Int -> p.toDouble()
                        else -> 0.0
                    }
                    val quantity = when (val q = item["quantity"]) {
                        is Int -> q
                        is Double -> q.toInt()
                        else -> 0
                    }
                    "$quantity x $name - RM ${"%.2f".format(price * quantity)}"
                }
            )
            orderItemsList.adapter = adapter
            orderSubtotal.text = "RM ${"%.2f".format(subtotal)}"
            orderTax.text = "RM ${"%.2f".format(tax)}"
            orderTotal.text = "RM ${"%.2f".format(total)}"
        }
    }

    fun showDefaultView() {
            orderDetailsContainer.visibility = View.GONE
            splashView.visibility = View.VISIBLE
    }
}

// MainActivity.kt
class MainActivity : FlutterActivity() {
    private var customerDisplay: CustomerDisplay? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dual_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showCustomerScreen" -> {
                        showCustomerScreen()
                        result.success(null)
                    }
                    "hideCustomerScreen" -> {
                        hideCustomerScreen()
                        result.success(null)
                    }
                    "updateOrderDisplay" -> {
                        val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        val subtotal = call.argument<Double>("subtotal") ?: 0.0
                        val tax = call.argument<Double>("tax") ?: 0.0
                        val total = call.argument<Double>("total") ?: 0.0
                        customerDisplay?.updateOrderDetails(items, subtotal, tax, total)
                        result.success(null)
                    }
                    "showDefaultDisplay" -> {
                        customerDisplay?.showDefaultView()
                        result.success(null)
                    }
                    else -> {
                        customerDisplay?.showDefaultView()
                        result.notImplemented()
                    }
                }
            }
    }

    private fun showCustomerScreen() {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val displays = displayManager.displays
        if (displays.size > 1) {
            val secondaryDisplay = displays[1]
            customerDisplay = CustomerDisplay(this, secondaryDisplay)
            customerDisplay?.show()
        }
    }

    private fun hideCustomerScreen() {
        customerDisplay?.dismiss()
        customerDisplay = null
    }
}
