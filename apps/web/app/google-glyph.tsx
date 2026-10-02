import Image from 'next/image';
import { GOOGLE_BRAND_IMAGE_URI, UI_TOKENS } from '@gymloop/shared';

/** Official Google gradient mark, shared unmodified by every provider button. */
export function GoogleGlyph() {
  return <Image src={GOOGLE_BRAND_IMAGE_URI} alt="" aria-hidden="true" className="provider-glyph" width={UI_TOKENS.icons.controlSize} height={UI_TOKENS.icons.controlSize} unoptimized />;
}
