import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const member = ['page.tsx', 'activity/page.tsx', 'check-in/page.tsx', 'my-gym/page.tsx', 'add-ons/page.tsx', 'messages/page.tsx', 'member-navigation.tsx', 'you-settings.tsx', 'layout.tsx'];
const consoleFiles = ['layout.tsx', 'dashboard/page.tsx', 'dashboard/metrics-dashboard.tsx', 'console/page.tsx', 'console/member-search-page.tsx', 'console/check-in/check-in-gate.tsx', 'console/check-in/poster/page.tsx', 'red-list/page.tsx', 'members/new/page.tsx', 'members/member-form.tsx', 'members/[memberId]/page.tsx', 'members/[memberId]/edit/page.tsx', 'memberships/page.tsx', 'memberships/[memberId]/page.tsx', 'payments/page.tsx', 'messages/page.tsx', 'messages/message-forms.tsx', 'leads/page.tsx', 'leads/lead-forms.tsx'];
// Exact diagnostic/INV literals stay pinned. Broad pattern exemptions would
// conceal newly hardcoded chrome, so every exception is local to its file.
const stays: Record<string, readonly string[]> = {
  '(console)/console/member-search-page.tsx': ['The member list could not be loaded.'],
  '(console)/members/[memberId]/page.tsx': ['Your gym'],
  '(console)/memberships/[memberId]/page.tsx': [
    'That form did not name a member.', 'No plan of this gym has that id.',
    'This member already has a live membership. Let it expire, or cancel it, before selling another.',
    'This gym has no settings row, so nobody is named as its pause approver.',
    'Only the role this gym names as its pause approver may decide a pause.',
    "That would take this member past the gym's freeze allowance for the year.",
    'That membership belongs to a different member.',
    'A payment for this member, of this amount and method, was recorded moments ago — so this one was not. If it is a genuinely separate payment, record it again from this page.',
  ],
  '(console)/payments/page.tsx': [
    'Something this payment would create already exists, so nothing was recorded. Reload the member’s page and take it again.',
    'That membership belongs to a different member.',
  ],
  '(console)/messages/page.tsx': ['held back because the member opted out.'],
  '(console)/messages/message-forms.tsx': ['This member has opted out or is no longer eligible. No message link was created.'],
  '(console)/leads/lead-forms.tsx': [
    'That phone belongs to a member who cannot be linked right now.',
    'An existing member already owns this phone. Link the lead to that member explicitly.',
    'An existing member already owns this phone. Confirm the explicit link for',
    'An existing member already owns this phone, but their details could not be shown here. Reload the screen and start the conversion again.',
    'The connection was interrupted. The outcome is uncertain. Retry the conversion — it won’t create a second member.',
  ],
  // BIZ-F3 preserves platform operator chrome; tenant metrics still vary.
  'platform/[id]/page.tsx': ['That gym is not available.', 'We couldn’t load this gym’s details. Please try again.', 'All gyms', 'Gym code ·', 'Manage gym'],
};
const files = [...member.map((file) => `member/${file}`), ...consoleFiles.map((file) => `(console)/${file}`), 'platform/[id]/page.tsx'];

describe('BIZ-012/013 copy audit', () => {
  it.each(files)('%s contains no default-vertical text outside exact Stays literals', (file) => {
    const source = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
    const tree = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
    const offenders: string[] = [];
    const visit = (node: ts.Node) => {
      const attribute = node.parent && ts.isJsxAttribute(node.parent) ? node.parent.name.getText(tree) : null;
      // Class names, URLs and identifiers are explicitly outside the copy contract.
      const identifier = attribute !== null && !['aria-label', 'title', 'alt', 'placeholder', 'label'].includes(attribute);
      if (!identifier && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node) || ts.isJsxText(node) || ts.isTemplateHead(node) || ts.isTemplateMiddle(node) || ts.isTemplateTail(node))) {
        const text = node.text.replace(/\s+/g, ' ').trim();
        if (/\s/.test(text) && /\b(gym|member|members|trainer)\b/i.test(text) && !(stays[file] ?? []).includes(text)) offenders.push(text);
      }
      ts.forEachChild(node, visit);
    };
    visit(tree);
    expect(offenders).toEqual([]);
  });
});
