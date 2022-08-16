// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../interfaces/IJoinable.sol';
import '../interfaces/IInsuredPool.sol';
import '../insurer/Rounds.sol';

import 'hardhat/console.sol';

/// @title InsurerJoinBase
/// @notice Handles Insured's requests on joining this Insurer
abstract contract InsurerJoinBase is IJoinEvents {
  function internalGetStatus(address) internal view virtual returns (InsuredStatus);

  function internalSetStatus(address, InsuredStatus) internal virtual;

  function internalIsInvestor(address) internal view virtual returns (bool);

  function internalRequestJoin(address insured) internal virtual returns (InsuredStatus status) {
    require(Address.isContract(insured));
    if ((status = internalGetStatus(insured)) >= InsuredStatus.Joining) {
      return status;
    }
    if (status == InsuredStatus.Unknown) {
      require(!internalIsInvestor(insured));
    }
    internalSetStatus(insured, InsuredStatus.Joining);
    emit JoinRequested(insured);

    if ((status = internalInitiateJoin(insured)) != InsuredStatus.Joining) {
      status = _updateInsuredStatus(insured, status);
    }
  }

  function internalCancelJoin(address insured) internal returns (InsuredStatus status) {
    if ((status = internalGetStatus(insured)) == InsuredStatus.Joining) {
      status = InsuredStatus.JoinCancelled;
      internalSetStatus(insured, status);
      emit JoinCancelled(insured);
    }
  }

  function _updateInsuredStatus(address insured, InsuredStatus status) private returns (InsuredStatus) {
    require(status > InsuredStatus.Unknown);

    InsuredStatus currentStatus = internalGetStatus(insured);
    if (currentStatus == InsuredStatus.Joining) {
      bool accepted;
      if (status == InsuredStatus.Accepted) {
        if (internalPrepareJoin(insured)) {
          accepted = true;
        } else {
          status = InsuredStatus.JoinRejected;
        }
      } else if (status != InsuredStatus.Banned) {
        status = InsuredStatus.JoinRejected;
      }
      internalSetStatus(insured, status);

      bool isPanic;
      bytes memory errReason;

      try IInsuredPool(insured).joinProcessed(accepted) {
        emit JoinProcessed(insured, accepted);

        status = internalGetStatus(insured);
        if (accepted && status == InsuredStatus.Accepted) {
          internalAfterJoinOrLeave(insured, status);
        }
        return status;
      } catch Error(string memory reason) {
        errReason = bytes(reason);
      } catch (bytes memory reason) {
        isPanic = true;
        errReason = reason;
      }
      emit JoinFailed(insured, isPanic, errReason);
      status = InsuredStatus.JoinFailed;
    } else {
      if (status == InsuredStatus.Declined) {
        require(currentStatus != InsuredStatus.Banned);
      }
      if (currentStatus == InsuredStatus.Accepted && status != InsuredStatus.Accepted) {
        internalAfterJoinOrLeave(insured, status);
      }
    }

    internalSetStatus(insured, status);
    return status;
  }

  function internalAfterJoinOrLeave(address insured, InsuredStatus status) internal virtual {}

  function internalProcessJoin(address insured, bool accepted) internal virtual {
    _updateInsuredStatus(insured, accepted ? InsuredStatus.Accepted : InsuredStatus.JoinRejected);
  }

  function internalPrepareJoin(address) internal virtual returns (bool);

  function internalInitiateJoin(address) internal virtual returns (InsuredStatus);
}
