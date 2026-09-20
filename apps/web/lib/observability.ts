type JsonSafeValue = boolean | null | number | string | JsonSafeValue[] | { [key: string]: JsonSafeValue };

type OperationalEvent = {
  level: 'error' | 'info';
  event: string;
  timestamp: string;
  tenant_id?: string;
  correlation_id?: string;
  message?: string;
  context?: JsonSafeValue;
};

type LogDetails = {
  tenantId?: string;
  correlationId?: string;
  message?: string;
  context?: unknown;
};

type OperationalAdapter = (event: OperationalEvent) => void | Promise<void>;

type OperationalLoggerOptions = {
  write: OperationalAdapter;
  report?: OperationalAdapter;
  now?: () => string;
};

const REDACTED = '[REDACTED]';
const CIRCULAR = '[Circular]';
const UNSUPPORTED = '[Unsupported]';

const isSensitiveKey = (key: string): boolean => {
  const normalized = key.replace(/[^a-z0-9]/gi, '').toLowerCase();
  return normalized.includes('authorization')
    || normalized.includes('cookie')
    || normalized.includes('password')
    || normalized.includes('token')
    || normalized.includes('apikey')
    || normalized.includes('servicerole')
    || normalized.includes('secret')
    || normalized.includes('credential')
    || normalized.includes('email')
    || normalized.includes('phone')
    || normalized.includes('fullname');
};

const jsonSafeValue = (value: unknown, ancestors: WeakSet<object>): JsonSafeValue => {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') {
    return value;
  }

  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }

  if (typeof value !== 'object') {
    return UNSUPPORTED;
  }

  if (ancestors.has(value)) {
    return CIRCULAR;
  }

  ancestors.add(value);
  try {
    if (Array.isArray(value)) {
      return value.map((item) => jsonSafeValue(item, ancestors));
    }

    const result: { [key: string]: JsonSafeValue } = {};
    for (const [key, item] of Object.entries(value)) {
      result[key] = isSensitiveKey(key) ? REDACTED : jsonSafeValue(item, ancestors);
    }
    return result;
  } catch {
    return UNSUPPORTED;
  } finally {
    ancestors.delete(value);
  }
};

const send = (
  adapter: OperationalAdapter | undefined,
  event: OperationalEvent,
): void => {
  if (!adapter) {
    return;
  }

  try {
    void Promise.resolve(adapter(event)).catch(() => undefined);
  } catch {
    // Observability must not replace the failure being observed.
  }
};

/** Creates a structured logger that never sends raw sensitive context to an adapter. */
export function createOperationalLogger(options: OperationalLoggerOptions) {
  const emit = (level: OperationalEvent['level'], event: string, details: LogDetails = {}): OperationalEvent => {
    const loggedEvent: OperationalEvent = {
      level,
      event,
      timestamp: options.now?.() ?? new Date().toISOString(),
      ...(details.tenantId === undefined ? {} : { tenant_id: details.tenantId }),
      ...(details.correlationId === undefined ? {} : { correlation_id: details.correlationId }),
      ...(details.message === undefined ? {} : { message: details.message }),
      ...(details.context === undefined ? {} : { context: jsonSafeValue(details.context, new WeakSet()) }),
    };

    send(options.write, loggedEvent);
    if (level === 'error') {
      send(options.report, loggedEvent);
    }
    return loggedEvent;
  };

  return {
    info: (event: string, details?: LogDetails) => emit('info', event, details),
    error: (event: string, details?: LogDetails) => emit('error', event, details),
  };
}
