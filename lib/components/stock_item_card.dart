import 'package:flutter/material.dart';

class StockItemCard extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final double currentQty;
  final double reservedQty;
  final double availableQty;
  final double value; // Add this
  final String? image; // Add this
  final VoidCallback onStockIn;
  final VoidCallback onAdjustStock;

  const StockItemCard({
    Key? key,
    required this.itemCode,
    required this.itemName,
    required this.currentQty,
    required this.reservedQty,
    required this.availableQty,
    required this.value, // Add this
    this.image, // Add this
    required this.onStockIn,
    required this.onAdjustStock,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool canAdjustStock = currentQty > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // In the build method where the image is displayed:
                if (image != null && image!.isNotEmpty)
                  Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: NetworkImage(image!),
                        fit: BoxFit.cover,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: image!.contains('placeholder')
                        ? const Icon(Icons.fastfood, size: 30) // Fallback icon
                        : null,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Code: $itemCode',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      Text(
                        'Value: RM ${value.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildQuantityInfo('Current', currentQty),
                _buildQuantityInfo('Reserved', reservedQty),
                _buildQuantityInfo('Available', availableQty),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onStockIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Stock In',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: canAdjustStock
                        ? 'Adjust current stock quantity'
                        : 'Stock in first before adjusting',
                    child: ElevatedButton(
                        onPressed: canAdjustStock ? onAdjustStock : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canAdjustStock ? Colors.orange : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          'Adjust Stock',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  canAdjustStock ? Colors.white : Colors.black),
                        )),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityInfo(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value.toStringAsFixed(0),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
