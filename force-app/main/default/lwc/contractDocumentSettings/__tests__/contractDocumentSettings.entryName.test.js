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
  "@salesforce/apex/ContractDocumentSettingsController.issueOrgSettingsOperationKey",
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

const MASTER_LINKS = [
  { key: "glAccounts", label: "勘定科目", url: "/lightning/o/GlAccount__c/list" },
  {
    key: "conditionSets",
    label: "条件セット",
    url: "/lightning/o/GlConditionSet__c/list"
  },
  { key: "accountMaps", label: "割当", url: "/lightning/o/GlAccountMap__c/list" },
  {
    key: "tagRules",
    label: "タグルール",
    url: "/lightning/o/GlAccountingTagRule__c/list"
  },
  {
    key: "manualJournals",
    label: "手動仕訳",
    url: "/lightning/o/GlManualJournalSetting__c/list"
  }
];

function pageData(overrides = {}) {
  const { settings, settingLinks, ...rest } = overrides;
  return {
    orgWideEmailAddresses: [],
    hasAccountingMaster: false,
    settingLinks: [
      { key: "permissionSets", url: "/lightning/setup/PermSets/home" },
      {
        key: "documentCatalog",
        url: "/lightning/o/ContractDocumentTemplate__mdt/list?filterName=All"
      },
      { key: "estimateNotes", url: "/lightning/o/EstimateNoteMaster__c/list" },
      {
        key: "amountCalculation",
        url: "/lightning/o/GlAccountingSetting__mdt/list?filterName=All"
      }
    ],
    ...rest,
    settingLinks: settingLinks || [
      { key: "permissionSets", url: "/lightning/setup/PermSets/home" },
      {
        key: "documentCatalog",
        url: "/lightning/o/ContractDocumentTemplate__mdt/list?filterName=All"
      },
      { key: "estimateNotes", url: "/lightning/o/EstimateNoteMaster__c/list" },
      {
        key: "amountCalculation",
        url: "/lightning/o/GlAccountingSetting__mdt/list?filterName=All"
      }
    ],
    settings: {
      estimateSendMode: "PdfOnly",
      invoiceSendMode: "PdfOnly",
      estimateValidMonths: 1,
      defaultMonthlyCycles: 12,
      renewOpportunityEnabled: false,
      accountingEnabled: false,
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
      validationEnforce: false,
      lockExemptFieldApiNames: "Memo__c",
      paymentLockExemptFieldApiNames: "Memo__c",
      journalLockExemptFieldApiNames: "Memo__c",
      ...settings
    }
  };
}

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

describe("contractDocumentSettings headings 1-9 (Core 11.6)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  async function mount(data) {
    getSettings.mockResolvedValue(data);
    const { createElement } = require("lwc");
    const element = createElement("c-contract-document-settings", {
      is: ContractDocumentSettings
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    return element;
  }

  it("shows numbered headings 1-9 with inputs and links mixed", async () => {
    const element = await mount(pageData());
    const text = element.shadowRoot.textContent;
    const h2s = Array.from(element.shadowRoot.querySelectorAll("h2")).map(
      (node) => node.textContent.trim()
    );
    expect(h2s).toEqual([
      "1. 権限と共有",
      "2. 商品",
      "3. 帳票",
      "4. 送付",
      "5. 契約",
      "6. 追加項目",
      "7. 金額計算",
      "8. Accounting",
      "9. 入力とロック"
    ]);
    expect(text).toContain("行 3.1");
    expect(text).toContain("継続課金の既定サイクル数");
    expect(text).toContain("更新商談スイッチ");
    expect(text).toContain("見積備考");
    expect(text).not.toContain("帳票・送付");
    expect(text).not.toContain("組織の既定がありません");
    expect(text).not.toContain("既定帳票");
    expect(text).not.toContain("lightning-helptext");
    expect(element.shadowRoot.querySelector("lightning-helptext")).toBeNull();
  });

  it("shows カスタム入力規則をON as row 9.1 label", async () => {
    const element = await mount(pageData());
    const row = [...element.shadowRoot.querySelectorAll(".setting-row")].find(
      (node) => node.querySelector(".row-num")?.textContent.trim() === "行 9.1"
    );
    expect(row.querySelector(".row-label").textContent.trim()).toBe(
      "カスタム入力規則をON"
    );
    expect(row.querySelector("lightning-input").label).toBe(
      "カスタム入力規則をON"
    );
    expect(row.querySelector(".row-label").textContent).not.toBe("入力強制");
  });

  it("hides accounting master links without permission 21", async () => {
    const element = await mount(
      pageData({
        hasAccountingMaster: false,
        settingLinks: [
          { key: "permissionSets", url: "/lightning/setup/PermSets/home" },
          ...MASTER_LINKS
        ]
      })
    );
    const text = element.shadowRoot.textContent;
    expect(text).toContain("8. Accounting");
    expect(text).toContain("仕訳機能の利用有無");
    expect(text).not.toContain("行 8.7");
    expect(text).not.toContain("タグルール");
    expect(text).not.toContain("手動仕訳");
  });

  it("shows accounting master links when permission 21 is present", async () => {
    const element = await mount(
      pageData({
        hasAccountingMaster: true,
        settingLinks: [
          { key: "permissionSets", url: "/lightning/setup/PermSets/home" },
          ...MASTER_LINKS
        ]
      })
    );
    const text = element.shadowRoot.textContent;
    expect(text).toContain("8.7");
    expect(text).toContain("勘定科目");
    expect(text).toContain("条件セット");
    expect(text).toContain("割当");
    expect(text).toContain("タグルール");
    expect(text).toContain("手動仕訳");
  });

  it("renders one-option amount fields as readonly text without a lock badge", async () => {
    const element = await mount(pageData());
    const text = element.shadowRoot.textContent;
    expect(text).toContain("小数第2位の四捨五入");
    expect(text).toContain("注意");
    expect(text).toContain("変更しても保存済みは再計算しない");
    const quantityInput = element.shadowRoot.querySelector(
      '[name="quantityUnitPriceRoundingMode"]'
    );
    expect(quantityInput).toBeNull();
    const amountSection = [...element.shadowRoot.querySelectorAll("h2")]
      .find((node) => node.textContent.trim() === "7. 金額計算")
      .closest("section");
    expect(amountSection.textContent).not.toContain("変更不可");
  });

  it("shows freeze badges before and after policy freeze", async () => {
    const unfrozen = await mount(pageData({ settings: { policyFrozen: false } }));
    expect(unfrozen.shadowRoot.textContent).toContain("確定後は変更不可");
    const freezeHint =
      "最初の請求確定まで変えられる。確定後は104以外では戻せない";
    expect(unfrozen.shadowRoot.textContent).toContain(freezeHint);
    expect(unfrozen.shadowRoot.textContent.split(freezeHint).length - 1).toBe(6);
    document.body.removeChild(unfrozen);

    const frozen = await mount(
      pageData({
        settings: {
          policyFrozen: true,
          frozenByName: "固定者",
          frozenAtLabel: "2026-08-01"
        }
      })
    );
    const text = frozen.shadowRoot.textContent;
    expect(text).toContain("変更不可");
    expect(text).not.toContain("確定後は変更不可");
    expect(text).toContain("固定者");
    expect(text).toContain("2026-08-01");
  });
});

describe("contractDocumentSettings copy definition validation (Core 11.6)", () => {
  const getSettings = require("@salesforce/apex/ContractDocumentSettingsController.getSettings")
    .default;
  const validateFieldCopyDefinitions = require("@salesforce/apex/ContractDocumentSettingsController.validateFieldCopyDefinitions")
    .default;

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows optional copy-settings validation under heading 6 after freeze", async () => {
    getSettings.mockResolvedValue(
      pageData({
        settings: {
          policyFrozen: true,
          frozenByName: "固定者",
          frozenAtLabel: "2026-08-01"
        }
      })
    );
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

    const extraHeading = [...element.shadowRoot.querySelectorAll("h2")].find(
      (node) => node.textContent.trim() === "6. 追加項目"
    );
    expect(extraHeading).toBeTruthy();
    const extraSection = extraHeading.closest("section");
    expect(extraSection.textContent).toContain("コピー設定を検証");
    expect(extraSection.textContent).toContain("追加項目コピー");
    const validateButton = [
      ...extraSection.querySelectorAll("lightning-button")
    ].find((btn) => btn.label === "コピー設定を検証");
    expect(validateButton).toBeTruthy();
    expect(validateButton.disabled).toBe(false);
    const accountingHeading = [...element.shadowRoot.querySelectorAll("h2")].find(
      (node) => node.textContent.trim() === "8. Accounting"
    );
    expect(accountingHeading.closest("section").textContent).not.toContain(
      "コピー設定を検証"
    );

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
  const invoiceOrgWideRequired = Object.getOwnPropertyDescriptor(
    proto,
    "invoiceOrgWideRequired"
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

  it("requires invoice org sender only for PdfAndEmail", () => {
    expect(
      invoiceOrgWideRequired.call(ctx({ invoiceSendMode: "PdfAndEmail" }))
    ).toBe(true);
    expect(
      invoiceOrgWideRequired.call(ctx({ invoiceSendMode: "PdfOnly" }))
    ).toBe(false);
  });

  it("treats whitespace-only as blank", () => {
    expect(proto.isBlankSetting("   ")).toBe(true);
    expect(proto.isBlankSetting("会社")).toBe(false);
  });
});

describe("contractDocumentSettings send mode change (Core 11.3)", () => {
  const proto = ContractDocumentSettings.prototype;
  const sendModes = [
    { label: "使わない", stored: "Unused" },
    { label: "PDFのみ", stored: "PdfOnly" },
    { label: "PDFとメール送付", stored: "PdfAndEmail" }
  ];
  const saveSettings = require("@salesforce/apex/ContractDocumentSettingsController.saveSettings")
    .default;

  afterEach(() => {
    saveSettings.mockReset();
  });

  sendModes.forEach(({ label, stored }) => {
    it(`stores ${stored} when selecting ${label} for estimate and invoice`, () => {
      const instance = { settings: {} };
      proto.handleChange.call(instance, {
        target: { name: "estimateSendMode", value: label },
        detail: { value: stored }
      });
      proto.handleChange.call(instance, {
        target: { name: "invoiceSendMode", value: label },
        detail: { value: stored }
      });
      expect(instance.settings.estimateSendMode).toBe(stored);
      expect(instance.settings.invoiceSendMode).toBe(stored);
      proto.assertStoredSendModes.call(instance);
    });
  });

  sendModes.forEach(({ label, stored }) => {
    it(`saveSettings receives ${stored} after selecting ${label}`, async () => {
      saveSettings.mockResolvedValue({
        estimateSendMode: stored,
        invoiceSendMode: stored
      });
      const instance = {
        settings: {
          estimateSendMode: label,
          invoiceSendMode: label
        },
        template: {
          querySelectorAll: () => [
            { name: "estimateSendMode", value: stored },
            { name: "invoiceSendMode", value: stored }
          ]
        },
        reportValidity() {
          return true;
        },
        toast: jest.fn(),
        _pendingOperationKey: "op-1",
        saveSuccessMessage: "組織設定を保存しました。",
        applyNamedFieldValues: proto.applyNamedFieldValues,
        assertStoredSendModes: proto.assertStoredSendModes,
        message: proto.message
      };
      await proto.handleSave.call(instance);
      expect(saveSettings).toHaveBeenCalledTimes(1);
      const payload = saveSettings.mock.calls[0][0].input;
      expect(payload.estimateSendMode).toBe(stored);
      expect(payload.invoiceSendMode).toBe(stored);
      expect(payload.estimateSendMode).not.toBe(label);
      expect(payload.invoiceSendMode).not.toBe(label);
    });
  });

  it("errors and does not save when the stored value is the display label", async () => {
    const instance = {
      settings: {
        estimateSendMode: "PDFとメール送付",
        invoiceSendMode: "PDFとメール送付"
      },
      template: {
        querySelectorAll: () => [
          { name: "estimateSendMode", value: "PDFとメール送付" },
          { name: "invoiceSendMode", value: "PDFとメール送付" }
        ]
      },
      reportValidity() {
        return true;
      },
      toast: jest.fn(),
      _pendingOperationKey: "op-1",
      applyNamedFieldValues: proto.applyNamedFieldValues,
      assertStoredSendModes: proto.assertStoredSendModes,
      message: proto.message
    };
    await proto.handleSave.call(instance);
    expect(saveSettings).not.toHaveBeenCalled();
    expect(instance.toast).toHaveBeenCalledWith(
      "保存エラー",
      "見積書の3択が無い、空、または不正です。",
      "error"
    );
  });

  it("errors when invoice send mode is not a stored value", () => {
    const instance = {
      settings: {
        estimateSendMode: "PdfOnly",
        invoiceSendMode: "PDFのみ"
      }
    };
    expect(() => proto.assertStoredSendModes.call(instance)).toThrow(
      "請求書の3択が無い、空、または不正です。"
    );
  });
});
