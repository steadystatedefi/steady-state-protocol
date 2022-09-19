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

  function internalRequestJoin(address insured) internal virtual {
    Value.requireContract(insured);
    MemberStatus status = internalGetStatus(insured);
    if (status >= MemberStatus.Joining) {
      return;
    }
    if (status == MemberStatus.Unknown) {
      State.require(!internalIsInvestor(insured));
    }

    internalSetStatus(insured, MemberStatus.Joining);
    emit JoinRequested(insured);

    if ((status = internalInitiateJoin(insured)) != MemberStatus.Joining) {
      _updateInsuredStatus(insured, status);
    }
  }

  function internalCancelJoin(address insured) internal returns (MemberStatus status) {
    if ((status = internalGetStatus(insured)) == MemberStatus.Joining) {
      status = MemberStatus.JoinCancelled;
      internalSetStatus(insured, status);
      emit JoinCancelled(insured);
    }
  }

  function _updateInsuredStatus(address insured, MemberStatus status) private {
    Value.require(status > MemberStatus.Unknown);

    MemberStatus currentStatus = internalGetStatus(insured);
    if (status == currentStatus) {
      return;
    }

    bool accepted;
    if (currentStatus == MemberStatus.Joining) {
      if (status == MemberStatus.Accepted && internalPrepareJoin(insured)) {
        accepted = true;
        internalSetStatus(insured, status);
        IInsuredPool(insured).joinProcessed(accepted);
        currentStatus = internalGetStatus(insured);
      } else {
        if (status != MemberStatus.Banned) {
          status = MemberStatus.JoinRejected;
        }
        internalSetStatus(insured, currentStatus = status);

        uint256 resultType;
        bytes memory errReason;

        try IInsuredPool(insured).joinProcessed(accepted) {
          resultType = 2;
        } catch Error(string memory reason) {
          errReason = bytes(reason);
        } catch (bytes memory reason) {
          resultType = 1;
          errReason = reason;
        }
        if (resultType < 2) {
          emit JoinRejectionFailed(insured, resultType == 1, errReason);
        }
      }
      emit JoinProcessed(insured, accepted);
    } else {
      Value.require(status != MemberStatus.Accepted);
      State.require(currentStatus != MemberStatus.Banned);
      internalSetStatus(insured, status);
    }

    if (currentStatus == MemberStatus.Accepted) {
      if (!accepted) {
        emit MemberLeft(insured);
      }
      internalAfterJoinOrLeave(insured, status);
    }
  }

  function internalAfterJoinOrLeave(address insured, MemberStatus status) internal virtual;

  function internalProcessJoin(address insured, bool accepted) internal virtual {
    _updateInsuredStatus(insured, accepted ? MemberStatus.Accepted : MemberStatus.JoinRejected);
  }

  function internalPrepareJoin(address) internal virtual returns (bool);

  function internalInitiateJoin(address) internal virtual returns (MemberStatus);
}
