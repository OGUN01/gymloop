/**
 * Absolute URL for a sign-in-free page on the configured web origin (the same
 * base the app already uses for its API). Legal rows open these in the
 * in-app browser; the pages themselves live on the web app.
 */
export function publicPageUrl(webOrigin: string, path: string): string {
  return `${webOrigin.replace(/\/+$/, '')}${path}`;
}
