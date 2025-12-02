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
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.LinearLayout.LayoutParams
import android.graphics.Color


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
    private lateinit var orderDiscountLabel: TextView
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
        orderDiscountLabel = findViewById(R.id.orderDiscountLabel)
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
                .override(800,600)
                .thumbnail(0.1f)
                .placeholder(android.R.color.transparent)
                .error(android.R.drawable.ic_menu_report_image)
                .dontAnimate()
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
        taxRate: String,
        taxDetails: List<Map<String, Any>>? = null
    ) {
        handler.post {
            val taxContainer = findViewById<LinearLayout>(R.id.taxContainer)
            val singleTaxRow = findViewById<LinearLayout>(R.id.orderTaxRow)
            
            taxContainer.removeAllViews()
            
            if (!taxDetails.isNullOrEmpty()) {
                // Show multiple taxes container, hide single tax row
                taxContainer.visibility = View.VISIBLE
                singleTaxRow.visibility = View.GONE
                
                // Add each tax as a separate row
                taxDetails.forEach { taxDetail ->
                    val taxName = taxDetail["name"]?.toString() ?: "Tax"
                    val taxRateValue = when (val rate = taxDetail["rate"]) {
                        is Double -> rate
                        is Int -> rate.toDouble()
                        else -> 0.0
                    }
                    val taxAmount = when (val amount = taxDetail["amount"]) {
                        is Double -> amount
                        is Int -> amount.toDouble()
                        else -> 0.0
                    }
                    
                    if (taxRateValue > 0) {
                        val taxRow = createTaxRow(taxName, taxRateValue, taxAmount)
                        taxContainer.addView(taxRow)
                    }
                }
            } else {
                taxContainer.visibility = View.GONE
                singleTaxRow.visibility = 
                    if (taxRate == "0" || taxRate.isEmpty()) View.GONE else View.VISIBLE
                
                findViewById<TextView>(R.id.orderTaxLabel).text = "Tax (${taxRate}%):"
                findViewById<TextView>(R.id.orderTax).text = "RM ${"%.2f".format(tax)}"
            }
            
            // Create custom adapter for order items
            val adapter = object : ArrayAdapter<Map<String, Any>>(
                context,
                R.layout.order_item_layout,
                R.id.itemName,
                items
            ) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val view = convertView ?: layoutInflater.inflate(R.layout.order_item_layout, parent, false)
                    val item = getItem(position) ?: return view

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
                    val variantInfo = item["custom_variant_info"]

                    val priceAfterDiscount = price
                    val itemTotal = priceAfterDiscount * quantity

                    // Set basic item info
                    view.findViewById<TextView>(R.id.itemName).text = name
                    view.findViewById<TextView>(R.id.itemQuantity).text = quantity.toString()
                    view.findViewById<TextView>(R.id.itemPrice).text = "RM ${"%.2f".format(itemTotal)}"

                    // Handle variants (pill form)
                    val variantsContainer = view.findViewById<LinearLayout>(R.id.variantsContainer)
                    variantsContainer.removeAllViews()

                    if (variantInfo != null) {
                        val variants = parseVariants(variantInfo)
                        if (variants.isNotEmpty()) {
                            // Create rows for variants with proper wrapping
                            createVariantRows(variantsContainer, variants)
                        }
                    }

                    // Handle remarks
                    val remarksView = view.findViewById<TextView>(R.id.itemRemarks)
                    if (remarks.isNotEmpty()) {
                        remarksView.text = "Remarks: $remarks"
                        remarksView.visibility = View.VISIBLE
                    } else {
                        remarksView.visibility = View.GONE
                    }

                    // Handle serve later
                    val serveLaterView = view.findViewById<TextView>(R.id.serveLaterIndicator)
                    serveLaterView.visibility = if (serveLater) View.VISIBLE else View.GONE

                    return view
                }        
            }
            
            orderItemsList.adapter = adapter
            
            // Auto-scroll to the bottom
            orderItemsList.post {
                val adapter = orderItemsList.adapter
                if (adapter != null && adapter.count > 0) {
                    orderItemsList.setSelection(adapter.count - 1)
                }
            }
            
            orderSubtotal.text = "RM ${"%.2f".format(subtotal)}"
            orderTax.text = "RM ${"%.2f".format(tax)}"
            if(discount <= 0)
            {
                orderDiscountLabel.visibility = View.GONE
                orderDiscount.visibility = View.GONE
            }
            else
            {
                orderDiscountLabel.visibility = View.VISIBLE
                orderDiscount.visibility = View.VISIBLE

                val discountPercent = if (subtotal > 0) {
                    (discount / subtotal * 100)
                } else 0.0

                val percentText = "%.0f".format(discountPercent)  // e.g. "10"

                orderDiscountLabel.text = "Discount (${percentText}%):"
            }
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

    private fun parseVariants(variantInfo: Any?): List<String> {
        val variantList = mutableListOf<String>()
        
        try {
            when (variantInfo) {
                is String -> {
                    if (variantInfo.isEmpty()) return variantList
                    
                    // Try to parse as JSON first
                    if (variantInfo.trim().startsWith("[")) {
                        try {
                            val jsonArray = org.json.JSONArray(variantInfo)
                            for (i in 0 until jsonArray.length()) {
                                val variantGroup = jsonArray.getJSONObject(i)
                                val options = variantGroup.getJSONArray("options")
                                for (j in 0 until options.length()) {
                                    val option = options.getJSONObject(j)
                                    val optionName = option.getString("option")
                                    val additionalCost = option.optDouble("additional_cost", 0.0)
                                    
                                    if (additionalCost > 0) {
                                        variantList.add("$optionName (+RM ${"%.2f".format(additionalCost)})")
                                    } else {
                                        variantList.add(optionName)
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            // If JSON parsing fails, use regex to extract options
                            val regex = Regex("""option:\s*([^,}]+)(?:,\s*additional_cost:\s*([\d.]+))?""")
                            regex.findAll(variantInfo).forEach { match ->
                                val optionName = match.groupValues[1].trim()
                                val cost = match.groupValues.getOrNull(2)?.toDoubleOrNull() ?: 0.0
                                
                                if (optionName.isNotEmpty()) {
                                    if (cost > 0) {
                                        variantList.add("$optionName (+RM ${"%.2f".format(cost)})")
                                    } else {
                                        variantList.add(optionName)
                                    }
                                }
                            }
                        }
                    } else {
                        // Fallback: treat as already formatted string (newline or comma-separated)
                        variantList.addAll(
                            variantInfo.split(Regex("[\\n,]"))
                                .map { it.trim() }
                                .filter { it.isNotEmpty() }
                        )
                    }
                }
                is List<*> -> {
                    // If it's already a list of maps from Flutter
                    variantInfo.forEach { item ->
                        if (item is Map<*, *>) {
                            val options = item["options"]
                            if (options is List<*>) {
                                options.forEach { opt ->
                                    if (opt is Map<*, *>) {
                                        val optionName = opt["option"]?.toString()
                                        val additionalCost = when (val cost = opt["additional_cost"]) {
                                            is Double -> cost
                                            is Int -> cost.toDouble()
                                            is String -> cost.toDoubleOrNull() ?: 0.0
                                            else -> 0.0
                                        }
                                        
                                        if (optionName != null && optionName.isNotEmpty()) {
                                            if (additionalCost > 0) {
                                                variantList.add("$optionName (+RM ${"%.2f".format(additionalCost)})")
                                            } else {
                                                variantList.add(optionName)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return variantList
    }
    
    private fun createVariantRows(container: LinearLayout, variants: List<String>) {
        var currentRow: LinearLayout? = null
        val screenWidth = context.resources.displayMetrics.widthPixels * 0.8f
        
        variants.forEach { variant ->
            if (variant.isNotEmpty()) {
                // Measure the pill width
                val pillWidth = measurePillWidth(variant)
                
                // Check if we need a new row
                if (currentRow == null || isRowFull(currentRow!!, screenWidth, pillWidth)) {
                    currentRow = createNewRow()
                    container.addView(currentRow)
                }
                
                // Add pill to current row
                val pill = createVariantPill(variant)
                currentRow!!.addView(pill)
            }
        }
    }

    private fun createNewRow(): LinearLayout {
        return LinearLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            orientation = LinearLayout.HORIZONTAL
        }
    }

    private fun isRowFull(row: LinearLayout, maxWidth: Float, newPillWidth: Int): Boolean {
        var totalWidth = 0f
        
        for (i in 0 until row.childCount) {
            val child = row.getChildAt(i)
            child.measure(
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            totalWidth += child.measuredWidth.toFloat()
        }
        
        // Add the new pill width and some margin
        totalWidth += newPillWidth.toFloat() + 4.dpToPx().toFloat()
        
        return totalWidth > maxWidth
    }

    private fun measurePillWidth(variant: String): Int {
        val textView = TextView(context)
        textView.text = variant
        textView.textSize = 10f
        textView.setPadding(8.dpToPx(), 4.dpToPx(), 8.dpToPx(), 4.dpToPx())
        textView.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        return textView.measuredWidth
    }

    private fun createVariantPill(variant: String): TextView {
        return TextView(context).apply {
            text = variant
            textSize = 10f
            setTextColor(Color.parseColor("#666666"))
            setBackgroundResource(R.drawable.variant_pill_background)
            setPadding(8.dpToPx(), 4.dpToPx(), 8.dpToPx(), 4.dpToPx())
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = 4.dpToPx()
                bottomMargin = 2.dpToPx()
            }
        }
    }

    // FIX: Add the correct overload with 3 parameters (name, rate, amount)
    private fun createTaxRow(label: String, rate: Double, amount: Double): LinearLayout {
        return LinearLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
            }
            orientation = LinearLayout.HORIZONTAL
            weightSum = 1f
            
            // Tax label with rate
            TextView(context).apply {
                text = "$label (${"%.1f".format(rate)}%):"
                setTextColor(Color.parseColor("#666666"))
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    0.7f
                )
                addView(this)
            }
            
            // Tax amount
            TextView(context).apply {
                text = "RM ${"%.2f".format(amount)}"
                setTextColor(Color.parseColor("#666666"))
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    0.3f
                )
                gravity = android.view.Gravity.END
                addView(this)
            }
        }
    }

    private fun Int.dpToPx(): Int {
        return (this * context.resources.displayMetrics.density).toInt()
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
                        // Ensure display exists before updating
                        if (customerDisplay == null || !isDisplayStillValid()) {
                            showCustomerScreen()
                        }
                        
                        val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        val subtotal = call.argument<Double>("subtotal") ?: 0.0
                        val tax = call.argument<Double>("tax") ?: 0.0
                        val discount = call.argument<Double>("discount") ?: 0.0
                        val rounding = call.argument<Double>("rounding") ?: 0.0
                        val total = call.argument<Double>("total") ?: 0.0
                        val taxRate = call.argument<String>("taxRate") ?: ""
                        val taxDetails = call.argument<List<Map<String, Any>>>("taxDetails")

                        customerDisplay?.updateOrderDetails(items, subtotal, tax, discount, rounding, total, taxRate, taxDetails)
                        result.success(null)
                    }
                    "showDefaultDisplay" -> {
                        customerDisplay?.showDefaultView()
                        result.success(null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    private fun showCustomerScreen() {
        try {
            // Only create new display if one doesn't exist
            if (customerDisplay == null) {
                val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                val displays = displayManager.displays
                
                val secondaryDisplay = displays.find { 
                    it.displayId != Display.DEFAULT_DISPLAY && it.isValid 
                }
                
                if (secondaryDisplay != null) {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val baseUrl = prefs.getString("flutter.base_url", "https://asdf.byondwave.com") ?: "https://asdf.byondwave.com"
                    
                    customerDisplay = CustomerDisplay(this, secondaryDisplay, authToken, baseUrl)
                    customerDisplay?.show()
                } else {
                    println("No secondary display found")
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // Add a method to check if display is still valid
    private fun isDisplayStillValid(): Boolean {
        return customerDisplay?.display?.isValid == true
    }

    private fun hideCustomerScreen() {
        customerDisplay?.cleanup()   
        customerDisplay?.dismiss()
        customerDisplay = null
    }
}