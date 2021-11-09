// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../interfaces/IInsurerPool.sol';
import '../interfaces/IInsuredPool.sol';
import '../tools/tokens/ERC1363ReceiverBase.sol';

abstract contract InsurerPoolBase is IInsurerPool, ERC1363ReceiverBase {
  address private _collateral;

  enum ProfileStatus {
    Unknown,
    Investor,
    InsuredUnknown,
    InsuredRejected,
    InsuredDeclined,
    InsuredJoining,
    InsuredAccepted,
    InsuredBanned
  }

  struct Profile {
    ProfileStatus status;
    uint128 investorBalance;
  }

  mapping(address => Profile) private _profiles;

  constructor(address collateral_) {
    _collateral = collateral_;
  }

  function collateral() external view override returns (address) {
    return _collateral;
  }

  modifier onlyCollateralFund() {
    require(msg.sender == _collateral);
    _;
  }

  /// @dev ERC1363-like receiver, invoked by the collateral fund for transfers/investments from user.
  /// mints $IC tokens when $CC is received from a user
  function internalReceiveTransfer(
    address operator,
    address,
    uint256 value,
    bytes calldata data
  ) internal override onlyCollateralFund {
    Profile memory p = _profiles[operator];
    if (isInsured(p.status)) {
      // TODO return of funds from insured
      return;
    }
    if (p.status == ProfileStatus.Unknown) {
      if (value == 0) return;
      p.status = ProfileStatus.Investor;
    }
    if (p.status == ProfileStatus.Investor) {
      p.investorBalance += uint128(value);
      _profiles[operator] = p;
      internalHandleInvestment(operator, value, data);
      return;
    }
    revert();
  }

  function internalHandleInvestment(
    address investor,
    uint256 value,
    bytes memory data
  ) internal virtual;

  function charteredDemand() public pure virtual override returns (bool);

  event JoinRequested(address indexed insured);
  event JoinCancelled(address indexed insured);
  event JoinProcessed(address indexed insured, bool acceptec);

  function isInsured(ProfileStatus status) private pure returns (bool) {
    return status >= ProfileStatus.InsuredUnknown && status <= ProfileStatus.InsuredBanned;
  }

  function isKnownInsured(ProfileStatus status) private pure returns (bool) {
    return status > ProfileStatus.InsuredUnknown && status <= ProfileStatus.InsuredBanned;
  }

  function isInsuredOrUnknown(ProfileStatus status) private pure returns (bool) {
    return status == ProfileStatus.Unknown || isInsured(status);
  }

  /// @dev initiates evaluation of the insured pool by this insurer. May involve governance activities etc.
  /// IInsuredPool.joinProcessed will be called after the decision is made.
  function requestJoin(address insured) external override {
    _requestJoin(insured);
  }

  function _requestJoin(address insured) private returns (ProfileStatus status) {
    require(Address.isContract(insured));
    status = _profiles[insured].status;
    if (isInsuredOrUnknown(status)) {
      if (status >= ProfileStatus.InsuredJoining) {
        return status;
      }
      _profiles[insured].status = ProfileStatus.InsuredJoining;
      emit JoinRequested(insured);

      status = internalInitiateJoin(insured);
      if (status != ProfileStatus.InsuredJoining) {
        return _updateInsuredStatus(insured, status);
      }
    }
    return ProfileStatus.InsuredRejected;
  }

  function cancelJoin() external returns (ProfileStatus) {
    return _cancelJoin(msg.sender);
  }

  function _cancelJoin(address insured) private returns (ProfileStatus status) {
    status = _profiles[insured].status;
    if (status == ProfileStatus.InsuredJoining) {
      _profiles[insured].status = ProfileStatus.InsuredUnknown;
      emit JoinCancelled(insured);
    }
  }

  function _updateInsuredStatus(address insured, ProfileStatus status) private returns (ProfileStatus) {
    require(isInsured(status));

    ProfileStatus currentStatus = _profiles[insured].status;
    if (currentStatus == ProfileStatus.InsuredJoining) {
      bool accepted;
      if (status == ProfileStatus.InsuredAccepted) {
        accepted = true;
      } else if (status != ProfileStatus.InsuredBanned) {
        status != ProfileStatus.InsuredRejected;
      }
      _profiles[insured].status = status;

      IInsuredPool(insured).joinProcessed(accepted);
      emit JoinProcessed(insured, accepted);

      return _profiles[insured].status;
    } else if (status == ProfileStatus.InsuredBanned) {
      require(isInsuredOrUnknown(currentStatus));
    } else if (status == ProfileStatus.InsuredDeclined) {
      require(isKnownInsured(currentStatus));
    } else {
      revert();
    }

    _profiles[insured].status = status;
    return status;
  }

  function internalProcessJoin(address insured, bool accepted) internal virtual {
    _updateInsuredStatus(insured, accepted ? ProfileStatus.InsuredAccepted : ProfileStatus.InsuredRejected);
  }

  function internalInitiateJoin(address) internal virtual returns (ProfileStatus) {
    return ProfileStatus.InsuredAccepted;
  }

  function statusOf(address account) external view returns (ProfileStatus) {
    return _profiles[account].status;
  }
}
