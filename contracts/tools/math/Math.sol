// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

import '../Errors.sol';

library Math {
  function boundedSub(uint256 x, uint256 y) internal pure returns (uint256) {
    unchecked {
      return x <= y ? 0 : x - y;
    }
  }

  function boundedXSub(uint256 x, uint256 y) internal pure returns (uint256, uint256) {
    unchecked {
      return x <= y ? (uint256(0), y - x) : (x - y, 0);
    }
  }

  function boundedMaxSub(uint256 x, uint256 y) internal pure returns (uint256, uint256) {
    unchecked {
      return x <= y ? (uint256(0), x) : (x - y, y);
    }
  }

  function boundedSub128(uint128 x, uint256 y) internal pure returns (uint128) {
    unchecked {
      return x <= y ? 0 : uint128(x - y);
    }
  }

  function boundedXSub128(uint128 x, uint256 y) internal pure returns (uint128, uint256) {
    unchecked {
      return x <= y ? (uint128(0), y - x) : (uint128(x - y), 0);
    }
  }

  function boundedMaxSub128(uint128 x, uint256 y) internal pure returns (uint128, uint256) {
    unchecked {
      return x <= y ? (uint128(0), x) : (uint128(x - y), y);
    }
  }

  function addAbsDelta(
    uint256 x,
    uint256 y,
    uint256 z
  ) internal pure returns (uint256) {
    return y > z ? x + y - z : x + z - y;
  }

  function checkAssign(uint256 v, uint256 ref) internal pure {
    if (v != ref) {
      Errors.overflow();
    }
  }

  function asUint224(uint256 x) internal pure returns (uint224 v) {
    checkAssign(v = uint224(x), x);
    return v;
  }

  function asUint216(uint256 x) internal pure returns (uint216 v) {
    checkAssign(v = uint216(x), x);
    return v;
  }

  function asUint128(uint256 x) internal pure returns (uint128 v) {
    checkAssign(v = uint128(x), x);
    return v;
  }

  function asUint112(uint256 x) internal pure returns (uint112 v) {
    checkAssign(v = uint112(x), x);
    return v;
  }

  function asUint96(uint256 x) internal pure returns (uint96 v) {
    checkAssign(v = uint96(x), x);
    return v;
  }

  function asUint88(uint256 x) internal pure returns (uint88 v) {
    checkAssign(v = uint88(x), x);
    return v;
  }

  function asUint64(uint256 x) internal pure returns (uint64 v) {
    checkAssign(v = uint64(x), x);
    return v;
  }

  function asUint32(uint256 x) internal pure returns (uint32 v) {
    checkAssign(v = uint32(x), x);
    return v;
  }

  function asInt128(uint256 x) internal pure returns (int128 v) {
    checkAssign(uint128(v = int128(uint128(x))), x);
    return v;
  }

  function checkAdd(uint256 result, uint256 added) internal pure {
    if (result < added) {
      Errors.overflow();
    }
  }

  function overflowBits(uint256 value, uint256 bits) internal pure {
    if (value >> bits != 0) {
      Errors.overflow();
    }
  }

  function sqrt(uint256 y) internal pure returns (uint256 z) {
    if (y > 3) {
      z = y;
      uint256 x = (y >> 1) + 1;
      while (x < z) {
        z = x;
        x = (y / x + x) >> 1;
      }
    } else if (y != 0) {
      z = 1;
    }
  }

  // @notice Calculates floor(a×b÷denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
  /// @param a The multiplicand
  /// @param b The multiplier
  /// @param denominator The divisor
  /// @return result The 256-bit result
  /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
  function mulDiv(
    uint256 a,
    uint256 b,
    uint256 denominator
  ) internal pure returns (uint256 result) {
    // 512-bit multiply [prod1 prod0] = a * b
    // Compute the product mod 2**256 and mod 2**256 - 1
    // then use the Chinese Remainder Theorem to reconstruct
    // the 512 bit result. The result is stored in two 256
    // variables such that product = prod1 * 2**256 + prod0
    uint256 prod0; // Least significant 256 bits of the product
    uint256 prod1; // Most significant 256 bits of the product

    // solhint-disable no-inline-assembly
    assembly {
      let mm := mulmod(a, b, not(0))
      prod0 := mul(a, b)
      prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    // Handle non-overflow cases, 256 by 256 division
    if (prod1 == 0) {
      Arithmetic.require(denominator > 0);
      assembly {
        result := div(prod0, denominator)
      }
      return result;
    }

    // Make sure the result is less than 2**256.
    // Also prevents denominator == 0
    Arithmetic.require(denominator > prod1);

    ///////////////////////////////////////////////
    // 512 by 256 division.
    ///////////////////////////////////////////////

    // Make division exact by subtracting the remainder from [prod1 prod0]
    // Compute remainder using mulmod
    uint256 remainder;
    assembly {
      remainder := mulmod(a, b, denominator)
    }
    // Subtract 256 bit number from 512 bit number
    assembly {
      prod1 := sub(prod1, gt(remainder, prod0))
      prod0 := sub(prod0, remainder)
    }

    // Factor powers of two out of denominator
    // Compute largest power of two divisor of denominator.
    // Always >= 1.
    unchecked {
      uint256 twos = (type(uint256).max - denominator + 1) & denominator;
      // Divide denominator by power of two
      assembly {
        denominator := div(denominator, twos)
      }

      // Divide [prod1 prod0] by the factors of two
      assembly {
        prod0 := div(prod0, twos)
      }
      // Shift in bits from prod1 into prod0. For this we need
      // to flip `twos` such that it is 2**256 / twos.
      // If twos is zero, then it becomes one
      assembly {
        twos := add(div(sub(0, twos), twos), 1)
      }
      prod0 |= prod1 * twos;

      // Invert denominator mod 2**256
      // Now that denominator is an odd number, it has an inverse
      // modulo 2**256 such that denominator * inv = 1 mod 2**256.
      // Compute the inverse by starting with a seed that is correct
      // correct for four bits. That is, denominator * inv = 1 mod 2**4
      uint256 inv = (3 * denominator) ^ 2;
      // Now use Newton-Raphson iteration to improve the precision.
      // Thanks to Hensel's lifting lemma, this also works in modular
      // arithmetic, doubling the correct bits in each step.
      inv *= 2 - denominator * inv; // inverse mod 2**8
      inv *= 2 - denominator * inv; // inverse mod 2**16
      inv *= 2 - denominator * inv; // inverse mod 2**32
      inv *= 2 - denominator * inv; // inverse mod 2**64
      inv *= 2 - denominator * inv; // inverse mod 2**128
      inv *= 2 - denominator * inv; // inverse mod 2**256

      // Because the division is now exact we can divide by multiplying
      // with the modular inverse of denominator. This will give us the
      // correct result modulo 2**256. Since the precoditions guarantee
      // that the outcome is less than 2**256, this is the final result.
      // We don't need to compute the high bits of the result and prod1
      // is no longer required.
      result = prod0 * inv;
      return result;
    }
    // solhint-enable no-inline-assembly
  }
}
