import { serializeBusinessProduct } from "./businessProduct";

/**
 * 親の selectedProducts とローカル表示の同期判定用フィンガープリント。
 * 自 emit のエコーバックでは再 decorate しない。
 */
export function buildProductsFingerprint(products) {
  if (!Array.isArray(products) || products.length === 0) {
    return "[]";
  }
  try {
    return JSON.stringify(
      products.map((row) => serializeBusinessProduct(row) || null)
    );
  } catch {
    return `len:${products.length}`;
  }
}

/**
 * 親からの表示同期が必要か。
 * 直前に自分が emit した内容、または直近 sync 済みなら不要。
 */
export function shouldSyncProductsFromParent(
  parentProducts,
  lastEmittedFingerprint,
  lastSyncedFingerprint
) {
  const fingerprint = buildProductsFingerprint(parentProducts);
  if (
    fingerprint === lastEmittedFingerprint ||
    fingerprint === lastSyncedFingerprint
  ) {
    return false;
  }
  return true;
}
