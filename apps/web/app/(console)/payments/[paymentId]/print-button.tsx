'use client';

/**
 * The receipt's one print control. A client component only because
 * `window.print()` is a browser call; the print stylesheet in `money.css`
 * decides what reaches the paper, and hides this button from it.
 */
export function PrintReceiptButton() {
  return (
    <button type="button" className="cl-btn money-print-button print:hidden" onClick={() => window.print()}>
      Print receipt
    </button>
  );
}
