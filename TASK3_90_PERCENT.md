# SINDAR — Task 3 / cumulative 90%

This phase is implemented on `sindar-phase1` as real SQLite-backed functionality.

## Mobile dashboard
- Fixed phone geometry: 4 KPI cards in one horizontal row.
- Five quick actions in one row.
- Ten modules in a fixed 5 x 2 grid.
- RTL header with company selector, white/gold SINDAR header mark and compact tools.
- Welcome, branch and month filters stay on one row.
- Bottom navigation uses Android-safe bottom insets.
- Live dashboard metrics and recent operations are loaded from SQLite.
- Demo seed reproduces 146,500 sales, 68,750 purchases, 17,320 expenses and 28,450 profit for November 2026.
- Widget geometry tests cover 360x800 and 390x844.

## Automated double-entry ERP
- Sales: cash, bank or credit; B2C/B2B tax rules; 15% VAT; customer VAT/CR; operational PDF and ZATCA QR.
- Sales post revenue/output VAT and cost-of-goods-sold/inventory entries.
- Quotations persist buyer information and convert to invoices in one action.
- Purchases: registered credit supplier or transient cash/bank supplier; universal scanner; input VAT; stock and payable updates.
- Receipt/payment vouchers use editable multi-row payment tables, cash/bank settlement, invoice linking and Arabic amount spelling.
- Customer/supplier statements support date ranges, cumulative balances and PDF output.
- Financial claims use outstanding customer invoices.
- Quick and compound journals validate debit = credit before posting.
- Items update quantity on sales/purchases and support camera barcode capture.
- Party opening balances create both party-ledger movements and balanced opening journal entries.
- Assets support value, purchase date, annual depreciation rate and depreciation account.
- Custody and payroll are persisted; monthly payroll posts accounting entries and payment vouchers.
- Reports are live from journals/documents: income statement, receivables/payables, VAT, cash/bank and trial balance.

## Users, permissions and licensing
- Local users authenticate by login code + PIN.
- Detailed RBAC persists and enforces view/add/edit/delete/approve/print/profit permissions.
- `maxUsers` is enforced from the applied license policy.
- Master Admin stores organization/license/expiry/status/tax/country/currency/maxAllowedUsers and generates a signed QR/token.
- Client activation verifies the token and immediately applies tax/currency/user limits.
- Expired/stopped grants block operational modules while keeping settings/license activation reachable.
- Seller VAT is hidden/cleared when the owner locks tax mode.

## Documents
- Seller profile is stored locally and reused by operational invoice PDF generation.
- Buyer VAT and commercial registration are included on B2B invoice data/PDF.
- Dynamic footer contacts are persisted and reused by generated operational documents.
- Official letters open directly in the official-letter document mode.
- Invoice header uses QR; non-invoice documents use date/document number without QR.

## Verification
CI is required to pass `flutter analyze`, shared-core tests, Flutter tests and release APK builds for both `sindar_app` and `sindar_admin` before this phase is considered closed.
