/**
 * 親 wizardData から契約開始日を読む。
 */
export function resolveSavedContractStartDate(wizardData) {
  return (wizardData && wizardData.contractStartDate) || "";
}

/**
 * 親 wizardData から契約終了日を読む。
 * contractEndDate が正。Apex プリセット互換で endDate も受け入れる。
 */
export function resolveSavedContractEndDate(wizardData) {
  if (!wizardData) {
    return "";
  }
  return wizardData.contractEndDate || wizardData.endDate || "";
}
