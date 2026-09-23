import { PHASE8_MONITOR_DISPATCH } from '../packages/shared/src/config/constants.ts';

export default {
  async scheduled(event, env) {
    if (event?.cron !== PHASE8_MONITOR_DISPATCH.cron) {
      throw new Error('Unexpected monitor schedule');
    }

    const token = env?.GITHUB_ACTIONS_DISPATCH_TOKEN;
    if (typeof token !== 'string' || token.trim().length === 0) {
      throw new Error('Monitor dispatch credential unavailable');
    }

    let response;
    try {
      response = await fetch(PHASE8_MONITOR_DISPATCH.url, {
        method: 'POST',
        headers: {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Gymloop-monitor-dispatch',
        },
        body: JSON.stringify({
          ref: PHASE8_MONITOR_DISPATCH.ref,
          inputs: { force_test_alert: false },
        }),
      });
    } catch {
      console.error('Monitor dispatch failed: network');
      throw new Error('Monitor dispatch failed');
    }

    if (response.status !== PHASE8_MONITOR_DISPATCH.acceptedStatus) {
      console.error('Monitor dispatch failed: unexpected response status');
      throw new Error('Monitor dispatch failed');
    }
  },
};
