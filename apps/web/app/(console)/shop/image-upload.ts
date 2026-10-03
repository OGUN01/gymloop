'use client';
import { uploadMediaFile, type MediaUploadStage } from '../../../lib/media-upload';
export function uploadProductImage(file: File, onStage?: (stage: MediaUploadStage) => void): Promise<{ assetId: string }> { return onStage ? uploadMediaFile(file, 'product', onStage) : uploadMediaFile(file, 'product'); }
