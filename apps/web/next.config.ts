import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Playwright's frozen local origin is 127.0.0.1. Next otherwise blocks the
  // development client/HMR origin and leaves client controls unhydrated.
  allowedDevOrigins: ['127.0.0.1'],
  // Next 16 writes its own apps/web/AGENTS.md and apps/web/CLAUDE.md on every
  // dev start. Off, deliberately: this repo's AGENTS.md is a constitutional
  // file, and an agent working under apps/web loads the nearest one — a
  // generated file describing Next's conventions would sit above the rules
  // that fail CI, and nobody would have decided that.
  agentRules: false,
};

export default nextConfig;
