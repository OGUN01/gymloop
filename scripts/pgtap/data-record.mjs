/** Internal descriptor snapshot for the frozen native evidence verifiers. */
export function exactNativeDataRecord(value, fields) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  if (![Object.prototype, null].includes(Object.getPrototypeOf(value))) return null;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const keys = Reflect.ownKeys(descriptors);
  if (keys.length !== fields.length || !keys.every(key => fields.includes(key)
    && descriptors[key].enumerable && Object.hasOwn(descriptors[key], 'value'))) return null;
  return Object.fromEntries(fields.map(key => [key, descriptors[key].value]));
}
