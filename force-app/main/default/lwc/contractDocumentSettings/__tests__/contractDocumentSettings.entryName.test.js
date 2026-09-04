import ContractDocumentSettings from "c/contractDocumentSettings";

jest.mock(
  "@salesforce/apex/ContractDocumentSettingsController.getSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractDocumentSettingsController.saveSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractDocumentSettingsController.validateFieldCopyDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_20_Can_OrgSettings",
  () => ({ default: true }),
  { virtual: true }
);

describe("contractDocumentSettings entry name (Core 11.6)", () => {
  const proto = ContractDocumentSettings.prototype;
  const title = Object.getOwnPropertyDescriptor(proto, "settingsPageTitle").get;
  const saved = Object.getOwnPropertyDescriptor(proto, "saveSuccessMessage")
    .get;

  it("uses 組織設定 as the entry name", () => {
    expect(title.call({})).toBe("組織設定");
    expect(saved.call({})).toBe("組織設定を保存しました。");
  });
});

describe("contractDocumentSettings contract heading (Core 11.6)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows 契約 heading with cycles, valid months, and renew switch", async () => {
    const { createElement } = require("lwc");
    getSettings.mockResolvedValue({
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PdfOnly",
        estimateValidMonths: 1,
        defaultMonthlyCycles: 12,
        renewOpportunityEnabled: false,
        accountingEnabled: false
      },
      estimateDocumentTemplates: [],
      invoiceDocumentTemplates: [],
      estimateEmailTemplates: [],
      invoiceEmailTemplates: [],
      orgWideEmailAddresses: []
    });
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain("契約");
    expect(element.shadowRoot.textContent).toContain(
      "継続課金の既定サイクル数"
    );
    expect(element.shadowRoot.textContent).toContain("見積有効期間");
    expect(element.shadowRoot.textContent).toContain("更新商談を利用する");
  });
});

describe("contractDocumentSettings document heading (Core 11.6)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows 帳票・送付 heading with send modes, company, sender, and defaults", async () => {
    const { createElement } = require("lwc");
    getSettings.mockResolvedValue({
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PdfOnly",
        estimateValidMonths: 1,
        defaultMonthlyCycles: 12,
        accountingEnabled: false
      },
      estimateDocumentTemplates: [],
      invoiceDocumentTemplates: [],
      estimateEmailTemplates: [],
      invoiceEmailTemplates: [],
      orgWideEmailAddresses: []
    });
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("帳票・送付");
    expect(text).not.toContain("共通会社・送信元");
    const h2s = Array.from(element.shadowRoot.querySelectorAll("h2")).map(
      (node) => node.textContent
    );
    expect(h2s).toContain("帳票・送付");
    expect(h2s).not.toContain("見積");
    expect(h2s).not.toContain("請求");
    expect(h2s).not.toContain("関連設定");
    expect(h2s.filter((label) => label === "帳票・送付").length).toBe(1);
    expect(text).toContain("帳票テンプレート（カスタムメタデータ）");
    expect(text).toContain("送付メールカタログ（カスタムメタデータ）");
  });
});

describe("contractDocumentSettings amount calculation heading (Core 11.6 / 11.9)", () => {
  const proto = ContractDocumentSettings.prototype;
  const warning = Object.getOwnPropertyDescriptor(
    proto,
    "amountCalculationWarning"
  ).get;
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows 金額計算 heading and pre-save warning that saved amounts are not recalculated", async () => {
    expect(warning.call({})).toBe(
      "会社設定を後から変えても、保存済みの見積金額、請求税額、AllocatedTaxAmount__c、入出金割当、仕訳金額は再計算しません。これから行う計算だけが新しい設定を見ます。"
    );

    getSettings.mockResolvedValue({
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PdfOnly",
        estimateValidMonths: 1,
        defaultMonthlyCycles: 12,
        taxRoundingMode: "DOWN",
        quantityUnitPriceRoundingMode: "Scale2HalfUp",
        amountRoundingMode: "Scale0HalfUp",
        taxLineAllocationMethod: "SignedLargestRemainder",
        allocationTieBreak: "InvoiceLineStableOrder",
        monthlyBucketAmountMethod: "EqualSplit",
        taxScheduleAllocationMethod: "SignedRevenueRatio",
        paymentLineAllocationMethod: "OpenInclusiveRatio",
        accountBalanceAllocationMethod: "SameRate",
        documentGroupTaxAllocationMethod: "ExclusiveRatioLastAbsorbs",
        accountingEnabled: false
      },
      estimateDocumentTemplates: [],
      invoiceDocumentTemplates: [],
      estimateEmailTemplates: [],
      invoiceEmailTemplates: [],
      orgWideEmailAddresses: []
    });
    const { createElement } = require("lwc");
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain("金額計算");
    expect(element.shadowRoot.textContent).toContain(
      "保存済みの見積金額、請求税額、AllocatedTaxAmount__c、入出金割当、仕訳金額は再計算しません"
    );
    expect(element.shadowRoot.textContent).toContain("税額丸め");
    expect(element.shadowRoot.textContent).toContain("帳票グループ税込");
  });
});

describe("contractDocumentSettings input and system headings (Core 11.6)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows 入力 and システム headings with enforce and lock-exempt fields", async () => {
    getSettings.mockResolvedValue({
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PdfOnly",
        estimateValidMonths: 1,
        defaultMonthlyCycles: 12,
        validationEnforce: false,
        lockExemptFieldApiNames: "Memo__c,SentDate__c",
        paymentLockExemptFieldApiNames: "Memo__c",
        journalLockExemptFieldApiNames: "Memo__c",
        accountingEnabled: false
      },
      estimateDocumentTemplates: [],
      invoiceDocumentTemplates: [],
      estimateEmailTemplates: [],
      invoiceEmailTemplates: [],
      orgWideEmailAddresses: []
    });
    const { createElement } = require("lwc");
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain("入力");
    expect(element.shadowRoot.textContent).toContain(
      "顧客固有Validation Ruleの強制"
    );
    expect(element.shadowRoot.textContent).toContain("システム");
    expect(element.shadowRoot.textContent).toContain("請求ロック除外項目");
    expect(element.shadowRoot.textContent).toContain("入出金ロック除外項目");
    expect(element.shadowRoot.textContent).toContain("仕訳ロック除外項目");
  });
});

describe("contractDocumentSettings copy definition validation (Accounting 3.1)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;
  const validateFieldCopyDefinitions = require("@salesforce/apex/ContractDocumentSettingsController.validateFieldCopyDefinitions")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows optional copy-settings validation under Accounting方針 without placing copy definitions", async () => {
    getSettings.mockResolvedValue({
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PdfOnly",
        estimateValidMonths: 1,
        defaultMonthlyCycles: 12,
        accountingEnabled: false,
        policyFrozen: true,
        frozenByName: "固定者",
        frozenAtLabel: "2026-08-01"
      },
      estimateDocumentTemplates: [],
      invoiceDocumentTemplates: [],
      estimateEmailTemplates: [],
      invoiceEmailTemplates: [],
      orgWideEmailAddresses: []
    });
    validateFieldCopyDefinitions.mockResolvedValue(
      "コピー設定に不備はありません。"
    );
    const { createElement } = require("lwc");
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("Accounting方針");
    expect(text).toContain("コピー設定を検証");
    expect(text).not.toContain("追加項目コピー");
    const accountingHeading = [...element.shadowRoot.querySelectorAll("h2")].find(
      (node) => node.textContent === "Accounting方針"
    );
    expect(accountingHeading).toBeTruthy();
    const accountingSection = accountingHeading.closest("section");
    expect(accountingSection.textContent).toContain("コピー設定を検証");
    const validateButton = [...accountingSection.querySelectorAll("lightning-button")].find(
      (btn) => btn.label === "コピー設定を検証"
    );
    expect(validateButton).toBeTruthy();
    expect(validateButton.disabled).toBe(false);

    await element.handleValidateFieldCopy();
    expect(validateFieldCopyDefinitions).toHaveBeenCalled();
  });
});

describe("contractDocumentSettings required fields (Core 11.3.1 / 11.3.2 / 1.1.10)", () => {
  const proto = ContractDocumentSettings.prototype;
  const companyNameRequired = Object.getOwnPropertyDescriptor(
    proto,
    "companyNameRequired"
  ).get;
  const invoiceCompanyFieldsRequired = Object.getOwnPropertyDescriptor(
    proto,
    "invoiceCompanyFieldsRequired"
  ).get;
  const estimateDefaultDocumentRequired = Object.getOwnPropertyDescriptor(
    proto,
    "estimateDefaultDocumentRequired"
  ).get;
  const invoiceOrgWideRequired = Object.getOwnPropertyDescriptor(
    proto,
    "invoiceOrgWideRequired"
  ).get;
  const estimateDefaultEmailRequired = Object.getOwnPropertyDescriptor(
    proto,
    "estimateDefaultEmailRequired"
  ).get;

  function ctx(settings) {
    return {
      settings,
      isUsedSendMode: proto.isUsedSendMode,
      usesPdfSendMode: proto.usesPdfSendMode
    };
  }

  it("requires company name when estimate or invoice is used", () => {
    expect(
      companyNameRequired.call(
        ctx({ estimateSendMode: "PdfOnly", invoiceSendMode: "Unused" })
      )
    ).toBe(true);
    expect(
      companyNameRequired.call(
        ctx({ estimateSendMode: "Unused", invoiceSendMode: "Unused" })
      )
    ).toBe(false);
  });

  it("requires registration number and bank when invoice is used", () => {
    expect(
      invoiceCompanyFieldsRequired.call(
        ctx({ estimateSendMode: "PdfOnly", invoiceSendMode: "Unused" })
      )
    ).toBe(false);
    expect(
      invoiceCompanyFieldsRequired.call(
        ctx({ estimateSendMode: "Unused", invoiceSendMode: "PdfAndEmail" })
      )
    ).toBe(true);
  });

  it("requires default document when PDF is used", () => {
    expect(
      estimateDefaultDocumentRequired.call(
        ctx({ estimateSendMode: "PdfOnly" })
      )
    ).toBe(true);
    expect(
      estimateDefaultDocumentRequired.call(
        ctx({ estimateSendMode: "Unused" })
      )
    ).toBe(false);
  });

  it("requires invoice org sender and default email only for PdfAndEmail", () => {
    expect(
      invoiceOrgWideRequired.call(ctx({ invoiceSendMode: "PdfAndEmail" }))
    ).toBe(true);
    expect(
      invoiceOrgWideRequired.call(ctx({ invoiceSendMode: "PdfOnly" }))
    ).toBe(false);
    expect(
      estimateDefaultEmailRequired.call(
        ctx({ estimateSendMode: "PdfAndEmail" })
      )
    ).toBe(true);
    expect(
      estimateDefaultEmailRequired.call(ctx({ estimateSendMode: "PdfOnly" }))
    ).toBe(false);
  });

  it("treats whitespace-only as blank", () => {
    expect(proto.isBlankSetting("   ")).toBe(true);
    expect(proto.isBlankSetting("会社")).toBe(false);
  });
});

describe("contractDocumentSettings send mode change (Core 11.3)", () => {
  const proto = ContractDocumentSettings.prototype;

  it("saves PdfAndEmail from combobox detail, not the display label", () => {
    const instance = { settings: {} };
    proto.handleChange.call(instance, {
      target: { name: "estimateSendMode", value: "PDFとメール送付" },
      detail: { value: "PdfAndEmail" }
    });
    expect(instance.settings.estimateSendMode).toBe("PdfAndEmail");
    proto.handleChange.call(instance, {
      target: { name: "invoiceSendMode", value: "PDFとメール送付" },
      detail: { value: "PdfAndEmail" }
    });
    expect(instance.settings.invoiceSendMode).toBe("PdfAndEmail");
  });

  it("reads combobox option values before save", () => {
    const instance = {
      settings: {
        estimateSendMode: "PDFとメール送付",
        invoiceSendMode: "PDFとメール送付"
      },
      template: {
        querySelectorAll: () => [
          { name: "estimateSendMode", value: "PdfAndEmail" },
          { name: "invoiceSendMode", value: "PdfAndEmail" }
        ]
      }
    };
    proto.applyNamedFieldValues.call(instance);
    expect(instance.settings.estimateSendMode).toBe("PdfAndEmail");
    expect(instance.settings.invoiceSendMode).toBe("PdfAndEmail");
  });
});
