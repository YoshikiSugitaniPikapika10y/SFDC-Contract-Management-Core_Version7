/**
 * 備考マスタ上書き確認用の requestId を発行する。
 */
export function createConfirmRequestId(pendingCount = 0) {
  return `confirm-${Date.now()}-${pendingCount}`;
}

export function hasEstimateRemarksText(remarks) {
  return String(remarks || "").trim().length > 0;
}
