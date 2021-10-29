// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../dependencies/openzeppelin/contracts/Address.sol';
import '../interfaces/IInsurerPool.sol';

abstract contract InsurerPoolBase {
  address private _collateral;

  enum InsuredStatus {
    Unknown,
    Joining,
    Accepted,
    Rejected,
    PaidOut,
    Declined
  }

  struct InsuredEntry {
    InsuredStatus status;
    //
  }

  mapping(address => InsuredEntry) internal _insureds;

  function collateral() external view returns (address) {
    return _collateral;
  }

  modifier onlyCollateralFund() {
    require(msg.sender == _collateral);
    _;
  }

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  /// mints $IC tokens when $CC is received from a user
  function onTransferReceived(
    address operator,
    address from,
    uint256 value,
    bytes memory data
  ) external onlyCollateralFund returns (bytes4) {}

  function charteredDemand() public pure virtual returns (bool);

  event JoinRequested(address indexed insured);
  event JoinCancelled(address indexed insured);
  event JoinProcessed(address indexed insured, bool acceptec);

  //   /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  //   /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external returns (InsuredStatus status) {
    require(Address.isContract(insured));
    status = _insureds[insured].status;
    if (status == InsuredStatus.Unknown) {
      _insureds[insured].status = InsuredStatus.Joining;
      emit JoinRequested(insured);

      status = internalJoin(insured);
      if (status != InsuredStatus.Joining) {
        return _processJoin(insured, status == InsuredStatus.Accepted);
      }
    }
  }

  function cancelJoin() external returns (InsuredStatus) {
    return _cancelJoin(msg.sender);
  }

  function _cancelJoin(address insured) private returns (InsuredStatus status) {
    status = _insureds[insured].status;
    if (status == InsuredStatus.Joining) {
      _insureds[insured].status = InsuredStatus.Unknown;
      emit JoinCancelled(insured);
    }
  }

  function _processJoin(address insured, bool accepted) private returns (InsuredStatus status) {
    status = _insureds[insured].status;
    if (status == InsuredStatus.Joining) {
      status = accepted ? InsuredStatus.Accepted : InsuredStatus.Rejected;
      _insureds[insured].status = status;

      IInsuredPool(insured).joinProcessed(accepted);
      emit JoinProcessed(insured, accepted);
    }
  }

  function internalJoin(address) internal virtual returns (InsuredStatus) {
    return InsuredStatus.Joining;
  }

  function statusOf(address insured) external view returns (InsuredStatus) {
    return _insureds[insured].status;
  }
}
