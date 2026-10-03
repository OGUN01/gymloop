'use client';
import { useEffect, useRef, useState } from 'react';
import { mediaUploadRequestSchema, mediaRefusalMessage, shopProductDisplayRequestSchema } from '@gymloop/shared';
import { uploadProductImage } from './image-upload';
import type { ShopCategory, ShopProduct } from '../../../lib/shop-console';
import { useShopCommand, ShopCommandStatus } from '../../../lib/use-shop-command';
import { ShopImage } from '../../member/shop/shop-image';
export function ProductDisplayPanel({ product, categories }: { product: ShopProduct; categories: ShopCategory[] }) {
  const command = useShopCommand();
  const [open, setOpen] = useState(false);
  const [categoryId, setCategoryId] = useState(product.category_id ?? '');
  const [sortOrder, setSortOrder] = useState(product.sort_order);
  const [file, setFile] = useState<File | null>(null);
  const [remove, setRemove] = useState(false);
  const [stage, setStage] = useState('');
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const verifiedFile = useRef<{ file: File; assetId: string } | null>(null);
  const savePending = useRef(false);
  useEffect(() => { if (!file) { setPreviewUrl(null); return; } const url = URL.createObjectURL(file); setPreviewUrl(url); return () => URL.revokeObjectURL(url); }, [file]);
  async function save() {
    if (savePending.current || command.disabled || uploading || !navigator.onLine) return;
    savePending.current = true;
    setUploadError(null); setUploading(true);
    try {
      let imageAssetId = remove ? null : product.imageAssetId;
      if (file) {
        if (!mediaUploadRequestSchema.safeParse({ kind: 'product', mime: file.type, bytes: file.size }).success) { setUploadError(mediaRefusalMessage('upload_rejected')); return; }
        if (verifiedFile.current?.file === file) imageAssetId = verifiedFile.current.assetId;
        else { imageAssetId = (await uploadProductImage(file, phase => setStage(phase === 'uploading' ? 'Uploading photo…' : 'Verifying photo…'))).assetId; verifiedFile.current = { file, assetId: imageAssetId }; }
      }
      const body = shopProductDisplayRequestSchema.safeParse({ categoryId: product.kind === 'product' ? categoryId || null : null, sortOrder, imageAssetId });
      if (!body.success) { setStage(''); setUploadError('Check the category and display order, then try again.'); return; }
      setStage('Saving photo and category…');
      if (await command.send(`/api/shop/products/${product.id}`, body.data, 'Saved', 'PATCH')) { setStage(''); setFile(null); }
      else setStage('');
    } catch (error) { setUploadError(error instanceof Error ? error.message : mediaRefusalMessage('storage_unavailable')); setStage(''); }
    finally { savePending.current = false; setUploading(false); }
  }
  return <div><button className="cl-btn cl-btn--quiet" disabled={command.preview} onClick={() => setOpen(!open)}>Photo and category</button>{open ? <section className="cl-panel space-y-4" aria-label={`Photo and category for ${product.name}`}><h3>Photo and category</h3><ShopCommandStatus command={command} />{uploadError ? <p role="alert">{uploadError}</p> : null}{stage ? <p role="status">{stage}</p> : null}<label className="block">Photo<input className="cl-input min-h-11 w-full" type="file" accept="image/jpeg,image/png,image/webp" disabled={command.disabled || uploading} onChange={event => { const selected = event.target.files?.[0] ?? null; setFile(selected); setRemove(false); setStage(selected ? `Chosen: ${selected.name}` : ''); setUploadError(selected && !mediaUploadRequestSchema.safeParse({ kind: 'product', mime: selected.type, bytes: selected.size }).success ? mediaRefusalMessage('upload_rejected') : null); }} /></label><p className="cl-muted">JPEG, PNG or WebP, up to 2 MB. One image per item.</p>{previewUrl ? <ShopImage imageUrl={previewUrl} /> : null}<label className="flex items-center gap-3 min-h-11"><input className="min-h-11 min-w-11" type="checkbox" checked={remove} disabled={command.disabled || uploading} onChange={event => { setRemove(event.target.checked); setFile(null); }} />Remove current photo</label>{product.kind === 'product' ? <label className="block">Category<select className="cl-input min-h-11 w-full" disabled={command.disabled || uploading} value={categoryId} onChange={event => setCategoryId(event.target.value)}><option value="">Uncategorised</option>{categories.filter(category => category.is_active).map(category => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label> : null}<label className="block">Display order<input className="cl-input min-h-11 w-full" type="number" min={0} value={sortOrder} disabled={command.disabled || uploading} onChange={event => setSortOrder(Number(event.target.value))} /></label><button className="cl-btn" disabled={command.disabled || uploading || (file !== null && !mediaUploadRequestSchema.safeParse({ kind: 'product', mime: file.type, bytes: file.size }).success)} onClick={save}>{uploadError || command.error ? 'Retry' : 'Save'}</button><button className="cl-btn cl-btn--quiet" disabled={uploading || command.busy} onClick={() => setOpen(false)}>Close</button></section> : null}</div>;
}
