
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/models/report_summary.dart';
import '../../../core/network/api_client.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _apiClient = ApiClient();
  final _currencyFormat = NumberFormat('#,##0', 'en_KE');
  
  bool _isLoading = true;
  String? _error;
  ReportSummary? _summary;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/reports/summary');
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          setState(() {
            _summary = ReportSummary.fromJson(body['data']);
            _isLoading = false;
          });
          return;
        } else {
          print('API returned success=false: ${response.body}');
        }
      } else {
        print('API returned status ${response.statusCode}: ${response.body}');
      }
      
      // If we got here, something went wrong with the API or internet
      setState(() {
        _error = 'Please connect to the internet to view real-time reports.';
        _isLoading = false;
      });
    } catch (e) {
      print('Network exception: $e');
      setState(() {
        _error = 'Please connect to the internet to view real-time reports.';
        _isLoading = false;
      });
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReport,
            tooltip: 'Refresh Reports',
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _fetchReport,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchReport,
              color: Colors.teal,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Real-Time Insights',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Data is calculated live from the server.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  _buildStatCard(
                    'Total Outstanding',
                    'KES ${_currencyFormat.format(_summary!.totalOutstandingDebt)}',
                    Icons.account_balance_wallet,
                    Colors.red.shade600,
                  ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 16),

                  _buildStatCard(
                    'Total Customers',
                    '${_summary!.totalCustomers}',
                    Icons.people,
                    Colors.teal.shade600,
                  ).animate().fade(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 16),

                  _buildStatCard(
                    'Overstayed Debts (>30 Days)',
                    '${_summary!.overstayedDebtCount} Customers',
                    Icons.warning_amber_rounded,
                    Colors.orange.shade700,
                  ).animate().fade(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 16),

                  _buildStatCard(
                    'Highest Debt Customer',
                    _summary!.highestDebtCustomerName,
                    Icons.trending_up,
                    Colors.purple.shade600,
                  ).animate().fade(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 4),
                  if (_summary!.highestDebtAmount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Amount: KES ${_currencyFormat.format(_summary!.highestDebtAmount)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ).animate().fade(duration: 400.ms, delay: 350.ms),
                    
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
