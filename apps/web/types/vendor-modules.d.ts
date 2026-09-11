/**
 * Ambient types for the pinned untyped dependencies the member-import parser
 * uses. Each declaration mirrors exactly the surface the parser consumes —
 * anything beyond it is deliberately unmodeled so a new use is a conscious
 * edit, not a silent `any`.
 */

declare module 'saxen' {
  /** The attribute getter saxen hands to `openTag`: a live, same-event view. */
  export type SaxAttributes = Record<string, string>;

  /** Decodes XML character references in one attribute value or text chunk. */
  export type SaxEntityDecoder = (value: string) => string;

  export class Parser {
    constructor(options?: { proxy?: boolean });
    on(event: 'openTag', handler: (
      elementName: string,
      attrGetter: () => SaxAttributes,
      decodeEntities: SaxEntityDecoder,
      selfClosing: boolean,
      contextGetter: () => { line: number; column: number },
    ) => void): Parser;
    on(event: 'closeTag', handler: (
      elementName: string,
      decodeEntities: SaxEntityDecoder,
      selfClosing: boolean,
      contextGetter: () => { line: number; column: number },
    ) => void): Parser;
    on(event: 'text', handler: (
      value: string,
      decodeEntities: SaxEntityDecoder,
      contextGetter: () => { line: number; column: number },
    ) => void): Parser;
    on(event: 'cdata', handler: (
      value: string,
      contextGetter: () => { line: number; column: number },
    ) => void): Parser;
    on(event: 'error' | 'warn', handler: (error: Error) => void): Parser;
    /** Parses a complete document; returns the pending error, if any. */
    parse(xml: string): Error | null;
    /** Writes one chunk of a streamed document; returns itself. */
    write(xml: string): Parser;
    /** Ends a streamed document; returns any buffered-remainder error. */
    end(): Error | null;
    stop(): void;
    ns(map?: Record<string, string>): void;
  }

  export const decode: SaxEntityDecoder;
}
