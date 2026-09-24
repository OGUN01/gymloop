import type { Metadata } from 'next';
import Link from 'next/link';
import { PRODUCT_NAME, PUBLISHER_NAME, PUBLIC_PAGE_PATHS, SUPPORT_EMAIL } from '@gymloop/shared';

export const metadata: Metadata = { title: `Privacy policy | ${PRODUCT_NAME}`, description: `How ${PRODUCT_NAME} uses and keeps gym member and staff information.` };

export default function PrivacyPage() {
  return <main className="public-main">
    <header className="public-intro">
      <p className="cl-eyebrow">Your information</p>
      <h1 className="cl-title">Privacy policy</h1>
      <p className="public-lede">You should know what your gym records in {PRODUCT_NAME}, who decides how it is used, and how to ask about it.</p>
      <p className="public-effective">Effective 24 September 2026 · Operated by {PUBLISHER_NAME}</p>
    </header>

    <section className="public-section" aria-labelledby="privacy-about">
      <p className="cl-eyebrow">01 / The service</p>
      <h2 id="privacy-about" className="cl-section-title">What {PRODUCT_NAME} does</h2>
      <p>Gyms use {PRODUCT_NAME} to run check-ins, memberships, follow-ups, receipts and add-ons. Members use the app to check in and see their own visits, membership and receipts.</p>
      <p>For a gym&rsquo;s member and enquiry data, the gym decides why and how it is used: the gym is the data fiduciary. {PRODUCT_NAME}, operated by {PUBLISHER_NAME}, is the data processor working on the gym&rsquo;s behalf. For gym staff accounts and platform operations, Ductx is responsible as the data fiduciary.</p>
    </section>

    <section className="public-section" aria-labelledby="privacy-data">
      <p className="cl-eyebrow">02 / What we handle</p>
      <h2 id="privacy-data" className="cl-section-title">Information in {PRODUCT_NAME}</h2>
      <ul className="public-list">
        <li>Names, phone numbers and email addresses entered by the gym, with optional gender, date of birth and notes.</li>
        <li>Sign-in email and, if you choose Continue with Google, the name and email Google shares for sign-in.</li>
        <li>Check-in time and method; memberships, pauses and renewals; consent choices; follow-up and messages sent by the gym.</li>
        <li>Payments, refunds and receipts the gym records for money it collected outside {PRODUCT_NAME}, plus add-on orders. {PRODUCT_NAME} does not process card or UPI payments or store card details.</li>
        <li>Enquiries (leads) recorded by the gym, and staff account information.</li>
      </ul>
      <p>The camera reads your gym&rsquo;s check-in QR code on your device. No photos are uploaded from a QR scan.</p>
    </section>

    <section className="public-section" aria-labelledby="privacy-where">
      <p className="cl-eyebrow">03 / Where it goes</p>
      <h2 id="privacy-where" className="cl-section-title">Where the service runs</h2>
      <p>Supabase hosts the database and sign-in in Mumbai (ap-south-1). Vercel hosts the web app and API functions in Mumbai. Encrypted database backups are stored in Cloudflare R2. Google is involved only if you choose Continue with Google for sign-in.</p>
      <p>We do not sell personal data. No advertising or third-party tracking SDKs are built into the web or mobile apps; they also have no third-party analytics or crash-reporting SDKs. Your gym may send promotional messages only under your separate marketing-consent choice.</p>
    </section>

    <section className="public-section" aria-labelledby="privacy-retention">
      <p className="cl-eyebrow">04 / Retention</p>
      <h2 id="privacy-retention" className="cl-section-title">How long records stay</h2>
      <p>Our retention policy sets these periods. The automated cleanup and erasure workflow is not yet in place, and the durations await legal review. A request is reviewed with the gym; we cannot promise that all information is removed at once.</p>
      <ul className="public-list public-list--ruled">
        <li>Payments, refunds and invoices: 8 years from the transaction. These financial records cannot be erased early under the retention policy.</li>
        <li>Memberships and consents: 8 years from membership end and the consent decision, respectively. These contract and consent records cannot be erased early.</li>
        <li>Attendance: 3 years from the visit; identifying personal fields are then cleared under the policy.</li>
        <li>Member profile: 3 years after the last membership ends; personal fields are then cleared, while the record needed to link financial history remains.</li>
        <li>Follow-up history: 3 years after the case closes; identifying personal fields are then cleared under the policy.</li>
        <li>Enquiries (leads): 2 years from the last activity, then deleted under the policy if they have not become a member record.</li>
      </ul>
    </section>

    <section className="public-section" aria-labelledby="privacy-choices">
      <p className="cl-eyebrow">05 / Your choices</p>
      <h2 id="privacy-choices" className="cl-section-title">Ask your gym, or write to us</h2>
      <p>Ask your gym for access to your information, a correction, a portable copy or erasure. Erasure is subject to the records we must keep under the policy above. You can also withdraw marketing consent; marketing and service-message choices are separate, and withdrawing either stops that category of communication without removing its consent history. We do not assume service messages continue after you withdraw service consent.</p>
      <p>There is no self-service erasure button yet. For a request or grievance, contact your gym or email <a className="public-text-link" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. We handle member requests with the gym, including identity checks. You can also read <Link className="public-text-link" href={`${PUBLIC_PAGE_PATHS.deleteAccount}#request`}>how to request account deletion</Link>.</p>
      <p>{PRODUCT_NAME} is for gym members aged 13 and over. A gym may add a member under 18 only with a parent's or guardian's consent, which the gym collects and keeps; {PRODUCT_NAME} has no guardian-consent form of its own yet. {PRODUCT_NAME} shows no advertising, and a gym should send marketing messages to a member under 18 only with that parent's or guardian's consent. It is not for children under 13.</p>
    </section>
  </main>;
}
