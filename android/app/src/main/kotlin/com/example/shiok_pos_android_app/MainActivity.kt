package com.nicholas.shiok_pos_android_app

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
import com.bumptech.glide.Glide
import java.net.URL
import java.net.HttpURLConnection
import java.util.Scanner
import org.json.JSONObject
import com.bumptech.glide.load.engine.DiskCacheStrategy
import java.util.concurrent.Executors
import android.content.SharedPreferences


class CustomerDisplay(
    context: Context, 
    display: Display,  
    private val authToken: String?,
    private val baseUrl: String  
) : Presentation(context, display) {
    private lateinit var orderItemsList: ListView
    private lateinit var orderSubtotal: TextView
    private lateinit var orderTax: TextView
    private lateinit var orderDiscount: TextView
    private lateinit var orderRounding: TextView
    private lateinit var orderTotal: TextView
        private lateinit var orderTaxLabel: TextView 
    private lateinit var slideshowView: ImageView
    private lateinit var logoView: ImageView
    private val handler = Handler(Looper.getMainLooper())
    private val imageUrls = mutableListOf<String>()
    private var currentImageIndex = 0
    private val imageChangeInterval = 5000L // 5 seconds
    private val executor = Executors.newFixedThreadPool(4)

     // Runnable for changing images
    private val imageChangeRunnable = object : Runnable {
        override fun run() {
            if (imageUrls.isNotEmpty()) {
                currentImageIndex = (currentImageIndex + 1) % imageUrls.size
                loadImage(imageUrls[currentImageIndex])
                handler.postDelayed(this, imageChangeInterval)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.customer_screen)

        orderItemsList = findViewById(R.id.orderItemsList)
        orderSubtotal = findViewById(R.id.orderSubtotal)
        orderTax = findViewById(R.id.orderTax)
        orderDiscount = findViewById(R.id.orderDiscount)
        orderRounding = findViewById(R.id.orderRounding)
        orderTotal = findViewById(R.id.orderTotal)
        slideshowView = findViewById(R.id.videoView)
        logoView = findViewById(R.id.logoView)
        orderTaxLabel = findViewById(R.id.orderTaxLabel)

       // Start with default view
        showDefaultView()
    }

    private fun loadImage(url: String) {
    handler.post {
        Glide.with(context)
            .load(url)
            .diskCacheStrategy(DiskCacheStrategy.ALL)
            .override(800, 600)
            .thumbnail(0.1f) // Load a low-res thumbnail first
            .placeholder(android.R.color.transparent) // Add placeholder
            .error(android.R.drawable.ic_menu_report_image) // Add error image
            .dontAnimate() // Skip animations for better performance
            .into(slideshowView)
    }
}

    override fun onStop() {
        super.onStop()
        handler.removeCallbacks(imageChangeRunnable)
    }

    fun cleanup() {
        handler.removeCallbacks(imageChangeRunnable)
        executor.shutdownNow()
    }

    fun updateOrderDetails(
        items: List<Map<String, Any>>, 
        subtotal: Double, 
        tax: Double, 
        discount: Double,
        rounding: Double,
        total: Double,
        taxRate: String
    ) {
        handler.post {
            orderTaxLabel.text = "GST (${taxRate}%):"
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
                    
                    val priceAfterDiscount = price
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
    executor.execute {
        try {
            val apiUrl = "$baseUrl/api/method/shiok_pos.api.get_customer_facing_images"
            val url = URL(apiUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 10000 // 10 seconds
            connection.readTimeout = 10000

            authToken?.let { token ->
                connection.setRequestProperty("Authorization", token)
            }
            
            val responseCode = connection.responseCode
            if (responseCode == HttpURLConnection.HTTP_OK) {
                val inputStream = connection.inputStream
                val scanner = Scanner(inputStream).useDelimiter("\\A")
                val response = if (scanner.hasNext()) scanner.next() else ""
                
                val json = JSONObject(response)
                if (json.getBoolean("success")) {
                    val imagesArray = json.getJSONArray("message")
                    val newImageUrls = mutableListOf<String>()
                    for (i in 0 until imagesArray.length()) {
                        newImageUrls.add(imagesArray.getString(i))
                    }
                    
                    // Update UI on main thread
                    handler.post {
                        imageUrls.clear()
                        imageUrls.addAll(newImageUrls)
                        handler.removeCallbacks(imageChangeRunnable)
                        
                        if (imageUrls.isNotEmpty()) {
                            currentImageIndex = 0
                            loadImage(imageUrls[0])
                            handler.postDelayed(imageChangeRunnable, imageChangeInterval)
                        }
                    }
                }
            }
            connection.disconnect()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    }
}

class MainActivity : FlutterActivity() {
    private var customerDisplay: CustomerDisplay? = null
    private var authToken: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dual_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showCustomerScreen" -> {
                        authToken = call.argument<String>("authToken")
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
                        val taxRate = call.argument<String>("taxRate") ?: ""

                        customerDisplay?.updateOrderDetails(items, subtotal, tax, discount, rounding, total, taxRate)
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
            
            // Get base URL from SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val baseUrl = prefs.getString("flutter.base_url", "https://asdf.byondwave.com") ?: "https://asdf.byondwave.com"
            
            customerDisplay = CustomerDisplay(this, secondaryDisplay, authToken, baseUrl)
            customerDisplay?.show()
        }
    }

    private fun hideCustomerScreen() {
        customerDisplay?.cleanup()   
        customerDisplay?.dismiss()
        customerDisplay = null
    }
}