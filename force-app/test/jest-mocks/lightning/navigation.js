const { createTestWireAdapter } = require("@salesforce/wire-service-jest-util");

const Navigate = Symbol.for("NavigationMixin.Navigate");
const GenerateUrl = Symbol.for("NavigationMixin.GenerateUrl");

const CurrentPageReference = createTestWireAdapter(jest.fn());

function NavigationMixin(Base) {
  return class extends Base {
    [Navigate]() {}
    [GenerateUrl]() {
      return Promise.resolve("https://www.example.com");
    }
  };
}

NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

module.exports = {
  CurrentPageReference,
  NavigationMixin
};
