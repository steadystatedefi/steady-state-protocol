pragma solidity ^0.8.4;

import '../interfaces/IPriceFeedChainlinkV3.sol';

contract MockChainlinkV3 is IPriceFeedChainlinkV3 {
  int256 private answer_;
  uint256 private updatedAt_;

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return (0, answer_, 0, updatedAt_, 0);
  }

  function setAnswer(int256 _answer) external {
    answer_ = _answer;
  }

  function setUpdatedAt(uint256 at) external {
    updatedAt_ = at;
  }
}
