// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/upgradeability/VersionedInitializable.sol';

contract MockVersionedInitializable1 is VersionedInitializable {
  uint256 private constant revision = 1;

  string public name;

  function initialize(string memory name_) external initializer(revision) {
    name = name_;
  }

  function getRevision() internal pure override returns (uint256) {
    return revision;
  }
}

contract MockVersionedInitializable2 is VersionedInitializable {
  uint256 private constant revision = 2;

  string public name;

  function initialize(string memory name_) external initializer(revision) {
    name = name_;
  }

  function getRevision() internal pure override returns (uint256) {
    return revision;
  }
}
