# SINDAR Rental Workspace V2 — accounting and UI contract

Branch: `sindar-rental-v2` — no changes to `main` or existing release branch.

## Why this is distinct from selling stock
- **Sales**: items in `items` carry sales and purchase prices. Only invoices change quantity, and recorded prices remain immutable.
- **Rentals**: one identifiable unit in `rental_equipment` has five independent billing rates (hour/day/week/month/year), optional item catalog reference and its own return status.
- **Catalog link**: imports name, code, purchase and sale price for reference. This **does not transfer goods to fixed assets or decrement warehouse quantity**. It is deliberately non-posting until an asset acquisition/transfer workflow is built. Do not register a purchased piece of equipment in both books as an asset.
- **Price editing**: tap an existing stock item to edit purchase/sale list prices for future transactions.

## Rental invoice and receipts
- Each contract specifies customer, unit, integer quantity, start date/time, calculated due date and frozen unit rate.
- The contract document is recorded in `documents`, with separate `equipment_rentals` term details.
- Contract issuance: debit `1103` customer receivables; credit `2106` deferred rental revenue.
- On accrual: debit `2106`, credit `4104` equipment rental revenue. Calculated proportionally through the contractual time interval; missed month-end entries are booked in their respective historical months. Reopening is idempotent.
- Receipt: a `receipt_voucher` linked to the contract, correct customer, no overpayment; cash/bank debit and AR credit via existing ERP voucher service.
- Historic pre-V4 rental contracts remain marked `legacy` and retain prior recognized journal entries; V4 does not post them twice.

## Non-implemented controls (do not misrepresent as production ready)
- Asset purchase / capitalization / stock-to-fixed-asset transfer, and depreciation.
- Fixed-asset disposal accounting, gain/loss on equipment sale. Sale action is removed from the rental UI to prevent misuse of retail sales accounting.
- Security deposits and refundable guarantees (must be liabilities, not rental income).
- Early-return refund, contract amendment, overtime fees/extension and automated penalties.
- Fiscal close/locked periods, tax invoicing for rental invoices, production-level localized tax review.
- Accrual runs when the app opens reports/dashboard/rentals; no guaranteed background accrual when the app never runs.
- Real-device acceptance tests, including prior DB migration, Google authentication, PDF preview and backup restore.

**Accounting review is required before using this workspace for real customer financial records.**
