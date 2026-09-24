import type { Metadata } from 'next';
import Link from 'next/link';
import { PRODUCT_NAME, PUBLISHER_NAME, PUBLIC_PAGE_PATHS, SUPPORT_EMAIL } from '@gymloop/shared';

export const metadata: Metadata = { title: `Delete my account | ${PRODUCT_NAME}`, description: `How to ask your gym and ${PUBLISHER_NAME} to delete your ${PRODUCT_NAME} account and eligible data.` };

export default function DeleteAccountPage() {
  return <main className="public-main">
    <p className="cl-eyebrow">Account and data</p>
    <h1 className="cl-title public-delete-title">Delete my account</h1>
    <section id="request" className="public-request" aria-labelledby="request-title">
      <p className="cl-eyebrow">Start here</p>
      <h2 id="request-title" className="cl-section-title">How to request deletion</h2>
      <ol className="public-steps">
        <li>Email <a className="public-text-link" href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(`Delete my ${PRODUCT_NAME} account`)}`}>{SUPPORT_EMAIL}</a> from the address you sign in with, or ask your gym&rsquo;s front desk to help.</li>
        <li>Use the subject <strong>Delete my {PRODUCT_NAME} account</strong> and include your gym&rsquo;s name. You do not need to send your password or payment details.</li>
        <li>{PUBLISHER_NAME} will confirm your identity with your gym before deleting anything and respond within 30 days.</li>
      </ol>
      <p className="public-request-note">There is no self-service erasure button yet. Your gym decides how its member data is handled; we work with it on your request.</p>
    </section>
    <section className="public-section" aria-labelledby="delete-what">
      <p className="cl-eyebrow">What happens next</p>
      <h2 id="delete-what" className="cl-section-title">What can be removed</h2>
      <p>After verification, the request covers your {PRODUCT_NAME} sign-in account and personal fields in your member profile, attendance and follow-up history. We delete eligible enquiries (leads). If your sign-in also belongs to a separate gym staff or platform account, we review that identity separately rather than deleting someone else&rsquo;s access.</p>
      <p>The deletion workflow is not yet automated. We review each request with your gym and will tell you what can be cleared and what remains on hold; sending an email is a request, not instant deletion.</p>
    </section>
    <section className="public-section" aria-labelledby="delete-retained">
      <p className="cl-eyebrow">Records kept under policy</p>
      <h2 id="delete-retained" className="cl-section-title">What must stay for now</h2>
      <p>Our retention policy keeps payments, refunds, invoices, memberships and consent history for 8 years for Indian tax, book-keeping and record-keeping needs. These financial and consent records cannot be erased early. The policy keeps attendance, member profile and follow-up history for 3 years after the relevant visit, membership end or case close; personal fields are then cleared. Enquiries (leads) are kept for 2 years from their last activity before deletion if they did not become a member record. Durations are policy defaults awaiting legal review, not a claim that automatic cleanup already runs.</p>
      <p>Read the <Link className="public-text-link" href={PUBLIC_PAGE_PATHS.privacy}>privacy policy</Link> for more on data and your choices. For questions, email <a className="public-text-link" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.</p>
    </section>
  </main>;
}
