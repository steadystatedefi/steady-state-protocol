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
  function internalGetStatus(address) internal view virtual returns (MemberStatus);

  function internalSetStatus(address, MemberStatus) internal virtual;

  function internalIsInvestor(address) internal view virtual returns (bool);

  function internalRequestJoin(address insured) internal virtual returns (MemberStatus status) {
    Value.requireContract(insured);
    if ((status = internalGetStatus(insured)) >= MemberStatus.Joining) {
      return status;
    }
    if (status == MemberStatus.Unknown) {
      State.require(!internalIsInvestor(insured));
    }
    internalSetStatus(insured, MemberStatus.Joining);
    emit JoinRequested(insured);

    if ((status = internalInitiateJoin(insured)) != MemberStatus.Joining) {
      status = _updateInsuredStatus(insured, status);
    }
  }

  function internalCancelJoin(address insured) internal returns (MemberStatus status) {
    if ((status = internalGetStatus(insured)) == MemberStatus.Joining) {
      status = MemberStatus.JoinCancelled;
      internalSetStatus(insured, status);
      emit JoinCancelled(insured);
    }
  }

  function _updateInsuredStatus(address insured, MemberStatus status) private returns (MemberStatus) {
    State.require(status > MemberStatus.Unknown);

    MemberStatus currentStatus = internalGetStatus(insured);
    if (status == currentStatus) {
      return currentStatus;
    }

    if (currentStatus == MemberStatus.Joining || status == MemberStatus.JoinFailed) {
      bool accepted;
      if (status == MemberStatus.Accepted) {
        if (internalPrepareJoin(insured)) {
          accepted = true;
        } else {
          status = MemberStatus.JoinRejected;
        }
      } else if (status != MemberStatus.Banned) {
        status = MemberStatus.JoinRejected;
      }
      internalSetStatus(insured, status);

      bool isPanic;
      bytes memory errReason;

      try IInsuredPool(insured).joinProcessed(accepted) {
        emit JoinProcessed(insured, accepted);

        status = internalGetStatus(insured);
        if (accepted && status == MemberStatus.Accepted) {
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
      status = MemberStatus.JoinFailed;
    } else {
      State.require(status != MemberStatus.Accepted);
      State.require(currentStatus != MemberStatus.Banned);

      if (currentStatus == MemberStatus.Accepted) {
        internalAfterJoinOrLeave(insured, status);
        emit MemberLeft(insured);
      }
    }

    internalSetStatus(insured, status);
    return status;
  }

  function internalAfterJoinOrLeave(address insured, MemberStatus status) internal virtual;

  function internalProcessJoin(address insured, bool accepted) internal virtual {
    _updateInsuredStatus(insured, accepted ? MemberStatus.Accepted : MemberStatus.JoinRejected);
  }

  function internalPrepareJoin(address) internal virtual returns (bool);

  function internalInitiateJoin(address) internal virtual returns (MemberStatus);
}
