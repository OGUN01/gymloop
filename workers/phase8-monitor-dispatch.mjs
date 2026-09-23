import { PHASE8_MONITOR_DISPATCH } from '../packages/shared/src/config/constants.ts';

async function dispatch(url, inputName, token) {
  try {
    const response = await fetch(url, {
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
        inputs: { [inputName]: false },
      }),
    });
    if (response.status !== PHASE8_MONITOR_DISPATCH.acceptedStatus) {
      throw new Error('Unexpected dispatch response');
    }
  } catch {
    throw new Error('Monitor dispatch failed');
  }
}

export default {
  async scheduled(event, env) {
    if (event?.cron !== PHASE8_MONITOR_DISPATCH.cron) {
      throw new Error('Unexpected monitor schedule');
    }

    const token = env?.GITHUB_ACTIONS_DISPATCH_TOKEN;
    if (typeof token !== 'string' || token.trim().length === 0) {
      throw new Error('Monitor dispatch credential unavailable');
    }

    const results = await Promise.allSettled([
      dispatch(PHASE8_MONITOR_DISPATCH.url, 'force_test_alert', token),
      dispatch(PHASE8_MONITOR_DISPATCH.watchdogUrl, 'force_test_missing', token),
    ]);
    if (results.some((result) => result.status === 'rejected')) {
      console.error('Monitor dispatch failed');
      throw new Error('Monitor dispatch failed');
    }
  },
};
