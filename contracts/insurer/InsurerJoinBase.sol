// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '../tools/Errors.sol';
import '../interfaces/IJoinable.sol';
import '../interfaces/IInsuredPool.sol';
import '../libraries/Rounds.sol';

import 'hardhat/console.sol';

// InsurerJoinBase handles Insured's requests on joining this Insurer
abstract contract InsurerJoinBase is IJoinEvents {
  function internalGetStatus(address) internal view virtual returns (InsuredStatus);

  function internalSetStatus(address, InsuredStatus) internal virtual;

  function internalIsInvestor(address) internal view virtual returns (bool);

  function internalRequestJoin(address insured) internal returns (InsuredStatus status) {
    require(Address.isContract(insured));
    if ((status = internalGetStatus(insured)) >= InsuredStatus.Joining) {
      return status;
    }
    if (status == InsuredStatus.Unknown) {
      require(!internalIsInvestor(insured));
    }
    internalSetStatus(insured, InsuredStatus.Joining);
    emit JoinRequested(insured);

    internalPrepareJoin(insured);
    if ((status = internalInitiateJoin(insured)) != InsuredStatus.Joining) {
      return _updateInsuredStatus(insured, status);
    }

    return InsuredStatus.Joining;
  }

  function cancelJoin() external returns (InsuredStatus) {
    return _cancelJoin(msg.sender);
  }

  function _cancelJoin(address insured) private returns (InsuredStatus status) {
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
        accepted = true;
      } else if (status != InsuredStatus.Banned) {
        status = InsuredStatus.JoinRejected;
      }
      internalSetStatus(insured, status);

      try IInsuredPool(insured).joinProcessed(accepted) {
        emit JoinProcessed(insured, accepted);
        return internalGetStatus(insured);
      } catch Error(string memory reason) {
        // console.log('JoinFailed', reason);
        emit JoinFailed(insured, reason);
      } catch {
        // console.log('JoinFailedUnknown');
        emit JoinFailed(insured, '<unknown>');
      }
      status = InsuredStatus.JoinFailed;
    } else if (status == InsuredStatus.Declined) {
      require(currentStatus != InsuredStatus.Banned);
    }

    internalSetStatus(insured, status);
    return status;
  }

  function internalProcessJoin(address insured, bool accepted) internal virtual {
    _updateInsuredStatus(insured, accepted ? InsuredStatus.Accepted : InsuredStatus.JoinRejected);
  }

  function internalPrepareJoin(address) internal virtual;

  function internalInitiateJoin(address) internal virtual returns (InsuredStatus);
}
