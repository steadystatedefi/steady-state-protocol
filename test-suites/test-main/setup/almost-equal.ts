import BigNumber from 'bignumber.js';
import baseChai from 'chai';

function almostEqualAssertion(
  this: typeof chai.Assertion,
  expected: BigNumber,
  actual: BigNumber,
  message: string
): void {
  this.assert(
    expected.plus(new BigNumber(1)).eq(actual) ||
      expected.plus(new BigNumber(2)).eq(actual) ||
      actual.plus(new BigNumber(1)).eq(expected) ||
      actual.plus(new BigNumber(2)).eq(expected) ||
      expected.eq(actual),
    `${message} expected #{act} to be almost equal #{exp}`,
    `${message} expected #{act} to be different from #{exp}`,
    expected.toString(),
    actual.toString()
  );
}

export function almostEqual() {
  return function equal(
    chai: typeof baseChai,
    utils: { flag: (ctx: typeof chai.Assertion, key: string) => boolean }
  ): void {
    chai.Assertion.overwriteMethod(
      'almostEqual',
      (original: typeof chai.Assertion) =>
        function assertion(this: typeof chai.Assertion, value: BigNumber.Value, message: string) {
          if (utils.flag(this, 'bignumber')) {
            const expected = new BigNumber(value);
            // eslint-disable-next-line no-underscore-dangle
            const actual = new BigNumber(this._obj as BigNumber.Value);
            almostEqualAssertion.apply(this, [expected, actual, message]);
          } else {
            // TODO: use rest params instead
            // eslint-disable-next-line @typescript-eslint/ban-ts-comment
            // @ts-ignore
            // eslint-disable-next-line prefer-rest-params
            original.apply(this, arguments);
          }
        }
    );
  };
}
