import { purchaseRequestStatusWord } from '@gymloop/shared';

/** Member/desk shared wording re-exports the frozen shared status vocabulary. */
export const purchaseStatusLabel = purchaseRequestStatusWord;

/** The ruled status sequence a detail page always labels truthfully. */
export const purchaseStatusSequence = [
  { status: 'requested', word: 'Requested' },
  { status: 'owner_accepted', word: 'Accepted' },
  { status: 'payment_proof_uploaded', word: 'Pending verification' },
  { status: 'recorded', word: 'Payment recorded' },
] as const;
