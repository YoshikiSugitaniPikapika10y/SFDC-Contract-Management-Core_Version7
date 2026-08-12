# SFDC Contract Management Core

Salesforce DX project for contract management (billing accounts, contract services, contract history, contract products, invoice products).

## Init

```bash
git clone https://github.com/YoshikiSugitaniPikapika10y/SFDC-Contract-Management-Core.git
cd SFDC-Contract-Management-Core
npm install
sf org login web -a vscodeOrg
```

## Package contents

- Custom objects: `BillingAccount__c`, `ContractService__c`, `ContractHistory__c`, `ContractProduct__c`, `InvoiceProduct__c`, `EstimateNoteMaster__c`
- LWC / Apex for estimate creation, order wizard, invoice generation
- Flow: `SetEstimateRelateFields` は同梱し得るがパッケージ標準必須ではない（テナント自動化。詳細は `docs/仕様書.md` §2）
- Manifest: `manifest/package-full.xml`

## Tenant customization (no logic change required)

When deploying to another customer org, adjust these **values** only (behavior stays the same shape):

| Area                                        | Where                                                  |
| ------------------------------------------- | ------------------------------------------------------ |
| Opportunity Stage / RecordType for tests    | `ContractTenantTestConfig.cls`                         |
| Opportunity VR-related seed fields in tests | `ContractTenantTestConfig.applyExtraOpportunityFields` |
| Estimate PDF company name / address         | `EstimateDocumentService` branding constants           |
| Estimate PDF privacy policy URL             | `pages/EstimateDocumentPdf.page`                       |

Keep Apex ↔ LWC rule parity for Change billing events:
`ChangeBillingEventUtil.cls` and `lwc/estimateLineItemUtils`.

## Deploy

```bash
sf project deploy start -d force-app -o <target-org> --test-level NoTestRun
```

Run package tests:

```bash
sf apex run test --tests ContractLifecycleScenarioTest --tests EstimateCreateControllerTest --tests OrderCreateControllerTest -o <target-org> --wait 30
```

## Docs

- `docs/仕様書.md` — **仕様の正本**（重複なく最新仕様のみ）
- `docs/lwc-apex-required-fields.txt` — 必要項目の技術一覧（付録）
- `docs/機能対応表.csv` — 要件カバレッジ索引（詳細は仕様書を正とする）
