import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Next 16 writes its own apps/web/AGENTS.md and apps/web/CLAUDE.md on every
  // dev start. Off, deliberately: this repo's AGENTS.md is a constitutional
  // file, and an agent working under apps/web loads the nearest one — a
  // generated file describing Next's conventions would sit above the rules
  // that fail CI, and nobody would have decided that.
  agentRules: false,
};

export default nextConfig;
