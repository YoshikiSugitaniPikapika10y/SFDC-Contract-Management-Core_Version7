/**
 * decorateRow が付ける表示専用プロパティ。親へ送らない。
 */
export const UI_ONLY_PRODUCT_FIELDS = new Set([
  "invoiceTypeOptions",
  "isInvoiceTypeDisabled",
  "canCopyDatesFromAbove",
  "gridRowClass",
  "tableRowClass",
  "rowIndex",
  "canDelete",
  "canDuplicate",
  "displayAmount",
  "displayUnitPrice",
  "displayUnitName",
  "amountInvalid",
  "unitPriceInvalid",
  "typeBadgeLabel",
  "typeBadgeClass",
  "isEditable",
  "isCustomExpanded",
  "showCustomFieldsToggle",
  "isProductLocked",
  "showBillingType",
  "displayBillingType",
  "showPriceCycle",
  "priceCycleLabel",
  "showPriceMeta",
  "showQuantityUnit",
  "cycleCountDisplay",
  "displayInvoiceAnchor",
  "showInvoiceAnchor",
  "invoiceAnchorTitle",
  "isUnitPriceLocked",
  "isUnitPriceNan",
  "canEditAmount",
  "showAmountEntryButton",
  "showUnitPriceUnlock",
  "showAmountEntryRoundingDiff",
  "amountEntryBillingTotalLabel",
  "amountEntryRoundingDiffLabel",
  "amountEntryRoundingTitle",
  "showLineNumber",
  "lineNumberLabel",
  "rowClass",
  "changeGroupBoundary",
  "rowContext",
  "showAddRemakeButton",
  "groupPairId",
  "isGroupHeader",
  "isCustomDetailRow",
  "isSectionHeader",
  "customFieldInputs",
  "isCustomReadonly",
  "parentRowId",
  "groupHeaderTitle",
  "groupHeaderSubtitle",
  "groupHeaderClass",
  "groupHeaderRowClass",
  "showChangeFlow",
  "isSectionHeader"
]);

export function stripUiFields(row) {
  if (!row || typeof row !== "object") {
    return row;
  }
  const next = { ...row };
  for (const key of UI_ONLY_PRODUCT_FIELDS) {
    delete next[key];
  }
  return next;
}

/** 親 / Apex へ渡す業務フィールドのみ残す。 */
export function serializeBusinessProduct(row) {
  if (!row) {
    return null;
  }
  const cleaned = stripUiFields(row);
  const product = {
    id: cleaned.id,
    productId: cleaned.productId,
    productName: cleaned.productName || "",
    quantity: cleaned.quantity,
    unit: cleaned.unit,
    unitName: cleaned.unitName,
    billingType: cleaned.billingType,
    billingCycle: cleaned.billingCycle,
    unitPrice: cleaned.unitPrice,
    amount: cleaned.amount,
    startDate: cleaned.startDate,
    endDate: cleaned.endDate,
    invoiceType: cleaned.invoiceType,
    recordType: cleaned.recordType,
    typeLabel: cleaned.typeLabel,
    sourceContractProductId: cleaned.sourceContractProductId ?? null,
    pairId: cleaned.pairId ?? null,
    isReadonly: cleaned.isReadonly === true,
    isDuplicate: cleaned.isDuplicate === true,
    // Original は相殺行のため商品カスタムを送信しない（保存時もクリア）
    customFields:
      cleaned.recordType === "Original"
        ? {}
        : { ...(cleaned.customFields || {}) },
    productVisibilityContext: {
      ...(cleaned.productVisibilityContext || {})
    },
    amountEntryMode: cleaned.amountEntryMode === true,
    manualAmount: cleaned.amountEntryMode === true ? cleaned.manualAmount : null
  };
  if (cleaned.contractProductId) {
    product.contractProductId = cleaned.contractProductId;
  }
  return product;
}
