import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sindar_core/sindar_core.dart';

import '../theme/app_theme.dart';

class UniversalScannerScreen extends StatefulWidget {
  const UniversalScannerScreen({super.key});

  @override
  State<UniversalScannerScreen> createState() => _UniversalScannerScreenState();
}

class _UniversalScannerScreenState extends State<UniversalScannerScreen> {
  UniversalBarcodeResult? _result;
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    final result = UniversalBarcodeParser.parse(value);
    setState(() {
      _handled = true;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ماسح الباركود الشامل')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: MobileScanner(onDetect: _onDetect),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _result == null
                  ? const Center(
                      child: Text(
                        'وجّه الكاميرا إلى QR ضريبي ZATCA أو باركود صنف أو QR تجاري.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _ResultCard(
                      result: _result!,
                      onUse: () => Navigator.of(context).pop(_result),
                      onReset: () => setState(() {
                        _handled = false;
                        _result = null;
                      }),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onUse,
    required this.onReset,
  });

  final UniversalBarcodeResult result;
  final VoidCallback onUse;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final zatca = result.zatca;
    final commercial = result.commercial;
    final title = switch (result.kind) {
      BarcodePayloadKind.zatcaTaxInvoice => 'فاتورة ضريبية ZATCA',
      BarcodePayloadKind.sindarCommercialInvoice => 'فاتورة تجارية SINDAR',
      BarcodePayloadKind.generic => 'باركود/QR عام',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy2)),
            if (zatca != null) ...[
              Text('المورد: ${zatca.sellerName}'),
              Text('الرقم الضريبي: ${zatca.sellerVatNumber}'),
              Text('الإجمالي: ${zatca.invoiceTotal.toStringAsFixed(2)}'),
              Text('الضريبة: ${zatca.vatTotal.toStringAsFixed(2)}'),
            ],
            if (commercial != null) ...[
              Text('الجهة: ${commercial.sellerName}'),
              Text('رقم المستند: ${commercial.documentNumber}'),
              Text('الإجمالي: ${commercial.total.toStringAsFixed(2)} ${commercial.currencyCode}'),
            ],
            if (result.kind == BarcodePayloadKind.generic)
              SelectableText(result.rawValue, maxLines: 3),
            const Spacer(),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReset, child: const Text('مسح جديد'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: onUse, child: const Text('استخدام البيانات'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
