const fs = require("fs");
const path = require("path");

const issuePage = fs.readFileSync(
  path.join(__dirname, "../../../pages/EstimateDocumentIssue.page"),
  "utf8"
);

describe("EstimateDocumentIssue success navigation (Core 4.8 / 4.3.1)", () => {
  it("keeps preview and send as explicit success-surface actions", () => {
    expect(issuePage).not.toMatch(/postToEstimateHub/);
    expect(issuePage).toMatch(/sforce\.one\.navigateToURL/);
    expect(issuePage).toMatch(/\/lightning\/page\/filePreview\?recordIds=/);
    expect(issuePage).toMatch(
      /\/lightning\/action\/quick\/ContractHistory__c\.Estimate_Send/
    );
    expect(issuePage).toMatch(
      /cmc\.estimateSend\.initialContentDocumentId/
    );
    expect(issuePage).toMatch(/onclick="openIssuedPreviewIfAny\(\)"/);
    expect(issuePage).toMatch(/このファイルを送る/);
    expect(issuePage).not.toMatch(/\(function\s*\(\)\s*\{/);
    expect(issuePage).not.toMatch(
      /発行したファイルは標準 Files で確認できます。/
    );
  });
});
