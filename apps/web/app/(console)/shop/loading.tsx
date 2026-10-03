import '../../styles/shop.css';

export default function ShopLoading() {
  return <main className="shop-workspace cl-page space-y-5" aria-busy="true">
    <h1 className="cl-title">Shop</h1>
    <p role="status" aria-live="polite">Loading shop…</p>
    <ul className="cl-rows" aria-hidden="true">
      <li>
        <div className="shop-loading-row">
          <div className="cl-skeleton shop-loading-line" />
          <div className="cl-skeleton shop-loading-line shop-loading-line--short" />
        </div>
        <div className="cl-skeleton shop-loading-row-end" />
      </li>
    </ul>
  </main>;
}
