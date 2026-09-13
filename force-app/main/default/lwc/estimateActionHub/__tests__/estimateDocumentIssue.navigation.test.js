const fs = require("fs");
const path = require("path");

const issuePage = fs.readFileSync(
  path.join(__dirname, "../../../pages/EstimateDocumentIssue.page"),
  "utf8"
);

describe("EstimateDocumentIssue success navigation (Core 4.8 / 4.3.1)", () => {
  it("does not treat parent postMessage as handled after the hub iframe was removed", () => {
    expect(issuePage).not.toMatch(/postToEstimateHub/);
    expect(issuePage).toMatch(/sforce\.one\.navigateToURL/);
    expect(issuePage).toMatch(/\/lightning\/page\/filePreview\?recordIds=/);
    expect(issuePage).toMatch(
      /\/lightning\/action\/quick\/ContractHistory__c\.Estimate_Send/
    );
    expect(issuePage).toMatch(
      /cmc\.estimateSend\.initialContentDocumentId/
    );
  });
});
