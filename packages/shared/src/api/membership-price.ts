/** The agreed price of one membership period, in exact integer paise. */
export function membershipNetPrice(pricePaise: number, discountPaise: number): number {
  if (
    !Number.isSafeInteger(pricePaise) ||
    !Number.isSafeInteger(discountPaise) ||
    pricePaise < 0 ||
    discountPaise < 0 ||
    discountPaise > pricePaise
  ) {
    throw new RangeError('Membership price and discount must be valid integer paise amounts.');
  }
  return pricePaise - discountPaise;
}
