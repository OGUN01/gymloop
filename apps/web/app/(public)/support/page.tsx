import type { Metadata } from 'next';
import Link from 'next/link';
import { PRODUCT_NAME, PUBLISHER_NAME, PUBLIC_PAGE_PATHS, SUPPORT_EMAIL } from '@gymloop/shared';

export const metadata: Metadata = { title: `Support | ${PRODUCT_NAME}`, description: `Find the right contact for ${PRODUCT_NAME} account, gym membership and privacy questions.` };

export default function SupportPage() {
  return <main className="public-main">
    <header className="public-intro">
      <p className="cl-eyebrow">Here to help</p>
      <h1 className="cl-title">Support</h1>
      <p className="public-lede">Let&rsquo;s get your question to the people who can answer it.</p>
      <p className="public-effective">{PRODUCT_NAME} is operated by {PUBLISHER_NAME}</p>
    </header>
    <section className="public-section" aria-labelledby="support-gym">
      <p className="cl-eyebrow">Your gym first</p>
      <h2 id="support-gym" className="cl-section-title">Membership and visit questions</h2>
      <p>Contact your gym&rsquo;s front desk about your plan, check-ins, receipts, payments collected by the gym, add-ons or a detail the gym entered incorrectly. Your gym manages these records and can check them with you.</p>
    </section>
    <section className="public-section" aria-labelledby="support-platform">
      <p className="cl-eyebrow">{PRODUCT_NAME} support</p>
      <h2 id="support-platform" className="cl-section-title">Sign-in and service problems</h2>
      <p>For trouble signing in, a technical problem or a privacy grievance, email <a className="public-text-link" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. Tell us your gym&rsquo;s name, the email you sign in with, what you were trying to do and what happened. Do not send your password or payment card details.</p>
      <p>For access, correction, a copy of your data or an erasure request, you may also contact your gym. We handle member data requests with the gym and check identity before changing data.</p>
    </section>
    <section className="public-section" aria-labelledby="support-read">
      <p className="cl-eyebrow">Useful reading</p>
      <h2 id="support-read" className="cl-section-title">Learn more</h2>
      <ul className="public-list public-list--ruled">
        <li><Link className="public-text-link" href={PUBLIC_PAGE_PATHS.privacy}>Privacy policy</Link> explains what is held and how long.</li>
        <li><Link className="public-text-link" href={PUBLIC_PAGE_PATHS.terms}>Terms of use</Link> explains the gym&rsquo;s and your role.</li>
        <li><Link className="public-text-link" href={`${PUBLIC_PAGE_PATHS.deleteAccount}#request`}>Delete my account</Link> gives the request steps.</li>
      </ul>
    </section>
  </main>;
}
