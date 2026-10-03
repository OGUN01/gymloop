import '../../styles/shop.css';

export default function ShopLoading() {
  return <main className="shop-workspace cl-page space-y-5" aria-busy="true">
    <h1 className="cl-title">Shop</h1>
    <p role="status" aria-live="polite">Loading shop…</p>
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4" aria-hidden="true">
      <div className="cl-panel shop-loading-tile">
        <div className="cl-skeleton shop-loading-image" />
        <div className="cl-skeleton shop-loading-line" />
        <div className="cl-skeleton shop-loading-line shop-loading-line--short" />
      </div>
    </div>
  </main>;
}
