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

/** Internal dense own-data array snapshot shared by native evidence verifiers. */
export function exactNativeDataArray(value) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype) return null;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const length = descriptors.length?.value;
  if (!Number.isSafeInteger(length) || length < 0 || Reflect.ownKeys(descriptors).length !== length + 1) return null;
  const result = [];
  for (let index = 0; index < length; index++) {
    const descriptor = descriptors[String(index)];
    if (!descriptor || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) return null;
    result.push(descriptor.value);
  }
  return result;
}
