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
import android.net.Uri
import android.widget.VideoView


class CustomerDisplay(context: Context, display: Display) : Presentation(context, display) {
    private lateinit var orderItemsList: ListView
    private lateinit var orderSubtotal: TextView
    private lateinit var orderTax: TextView
    private lateinit var orderDiscount: TextView
    private lateinit var orderRounding: TextView
    private lateinit var orderTotal: TextView
    private lateinit var videoView: VideoView
    private lateinit var logoView: ImageView
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.customer_screen)

        orderItemsList = findViewById(R.id.orderItemsList)
        orderSubtotal = findViewById(R.id.orderSubtotal)
        orderTax = findViewById(R.id.orderTax)
        orderDiscount = findViewById(R.id.orderDiscount)
        orderRounding = findViewById(R.id.orderRounding)
        orderTotal = findViewById(R.id.orderTotal)
        videoView = findViewById(R.id.videoView)
        logoView = findViewById(R.id.logoView)

        // Setup video
        try {
            val videoPath = "android.resource://${context.packageName}/${R.raw.default_video}"
            videoView.setVideoURI(Uri.parse(videoPath))
            videoView.setOnPreparedListener { mp ->
                mp.isLooping = true
                mp.setVolume(0f, 0f) // Mute the video
            }
            videoView.start()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStop() {
        super.onStop()
        videoView.stopPlayback()
    }

    fun cleanup() {
        videoView.stopPlayback()
        videoView.setVideoURI(null)
    }

    fun updateOrderDetails(
        items: List<Map<String, Any>>, 
        subtotal: Double, 
        tax: Double, 
        discount: Double,
        rounding: Double,
        total: Double
    ) {
        handler.post {
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
                    val discountAmount = when (val d = item["discount_amount"]) {
                        is Double -> d
                        is Int -> d.toDouble()
                        else -> 0.0
                    }
                    val serveLater = item["custom_serve_later"] == true
                    val remarks = item["custom_item_remarks"]?.toString() ?: ""
                    val variantInfo = item["custom_variant_info"]?.toString() ?: ""
                    
                    val priceAfterDiscount = price - discountAmount
                    val itemTotal = priceAfterDiscount * quantity
                    
                    val serveStatus = if (serveLater) "[SERVE LATER]" else ""
                    val remarksText = if (remarks.isNotEmpty()) "\nRemarks: $remarks" else ""
                    val variantText = if (variantInfo.isNotEmpty()) "\nOptions: $variantInfo" else ""
                    
                    "$quantity x $name $serveStatus\nRM ${"%.2f".format(priceAfterDiscount)} x $quantity = RM ${"%.2f".format(itemTotal)}$remarksText$variantText"
                }
            )
            orderItemsList.adapter = adapter
            orderSubtotal.text = "RM ${"%.2f".format(subtotal)}"
            orderTax.text = "RM ${"%.2f".format(tax)}"
            orderDiscount.text = "RM ${"%.2f".format(discount)}"
            orderRounding.text = "RM ${"%.2f".format(rounding)}"
            orderTotal.text = "RM ${"%.2f".format(total)}"
        }
    }

    fun showDefaultView() {
        handler.post {
            videoView.start()
        }
    }
}

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
                    val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList<Map<String, Any>>()
                    val subtotal = call.argument<Double>("subtotal") ?: 0.0
                    val tax = call.argument<Double>("tax") ?: 0.0
                    val discount = call.argument<Double>("discount") ?: 0.0
                    val rounding = call.argument<Double>("rounding") ?: 0.0
                    val total = call.argument<Double>("total") ?: 0.0

                    customerDisplay?.updateOrderDetails(items, subtotal, tax, discount, rounding, total)
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
