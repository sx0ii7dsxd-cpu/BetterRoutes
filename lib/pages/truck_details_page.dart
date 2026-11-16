import 'package:flutter/material.dart';

import '../models/truck_model.dart';
import '../theme/app_colors.dart';

class TruckDetailsPage extends StatelessWidget {
  const TruckDetailsPage({required this.truck, super.key});

  final Truck truck;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Truck details'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.local_shipping_rounded,
                  color: purple,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truck.registrationNumber,
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        truck.approvalStatus.toUpperCase(),
                        style: const TextStyle(
                          color: purple,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _DetailCard(
              title: 'Vehicle information',
              rows: {
                'Registration': truck.registrationNumber,
                'Type': truck.truckType,
                'Capacity': truck.capacity,
                'Additional details': truck.details.isEmpty
                    ? 'None'
                    : truck.details,
              },
            ),
            const SizedBox(height: 14),
            _DetailCard(
              title: 'Driver',
              rows: {
                'Name': truck.driverName,
                'Contact': truck.driverContactNumber,
              },
            ),
            const SizedBox(height: 14),
            _DetailCard(
              title: 'Associations',
              rows: {
                'Business': truck.businessName ?? truck.businessId,
                'Warehouse': truck.warehouseName ?? truck.warehouseId,
                'Warehouse code': truck.warehouseCode ?? 'Unavailable',
              },
            ),
            const SizedBox(height: 14),
            _DetailCard(
              title: 'Record dates',
              rows: {
                'Created': _formatDate(truck.createdAt),
                'Modified': _formatDate(truck.updatedAt),
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      date.toLocal().toString().split('.').first;
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: purple,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...rows.entries.map(
            (MapEntry<String, String> entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      entry.key,
                      style: const TextStyle(color: mutedColor, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(color: textColor, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
