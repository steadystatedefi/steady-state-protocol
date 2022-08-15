// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * Ownership is transferred in 2 phases: current owner calls {transferOwnership}
 * then the new owner calls {acceptOwnership}.
 * The last owner can recover ownership with {recoverOwnership} before {acceptOwnership} is called by the new owner.
 *
 * When ownership transfer was initiated, this module behaves like there is no owner, until
 * either acceptOwnership() or recoverOwnership() is called.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract SafeOwnable {
  address private _lastOwner;
  address private _activeOwner;
  address private _pendingOwner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferring(address indexed previousOwner, address indexed pendingOwner);

  /// @dev Initializes the contract setting the deployer as the initial owner.
  constructor() {
    _activeOwner = msg.sender;
    _pendingOwner = msg.sender;
    emit OwnershipTransferred(address(0), msg.sender);
  }

  /// @dev Returns active owner
  function owner() public view virtual returns (address) {
    return _activeOwner;
  }

  function owners()
    public
    view
    returns (
      address lastOwner,
      address activeOwner,
      address pendingOwner
    )
  {
    return (_lastOwner, _activeOwner, _pendingOwner);
  }

  function _onlyOwner() private view {
    require(
      _activeOwner == msg.sender,
      _pendingOwner == msg.sender ? 'Ownable: caller is not the owner (pending)' : 'Ownable: caller is not the owner'
    );
  }

  /// @dev Reverts if called by any account other than the owner.
  /// Will also revert after transferOwnership() when neither acceptOwnership() nor recoverOwnership() was called.
  modifier onlyOwner() {
    _onlyOwner();
    _;
  }

  /**
   * @dev Initiate ownership renouncment. After cempletion of renouncment, the contract will be without an owner.
   * It will not be possible to call `onlyOwner` functions anymore. Can only be called by the current owner.
   *
   * NB! To complete renouncment, current owner must call acceptOwnershipTransfer()
   */
  function renounceOwnership() external onlyOwner {
    _initiateOwnershipTransfer(address(0));
  }

  /// @dev Initiates ownership transfer of the contract to a new account `newOwner`.
  /// Can only be called by the current owner. The new owner must call acceptOwnershipTransfer() to get the ownership.
  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), 'Ownable: new owner is the zero address');
    _initiateOwnershipTransfer(newOwner);
  }

  function _initiateOwnershipTransfer(address newOwner) private {
    emit OwnershipTransferring(msg.sender, newOwner);
    _pendingOwner = newOwner;
    _lastOwner = _activeOwner;
    _activeOwner = address(0);
  }

  /// @dev Accepts ownership of this contract. Can be called:
  // - by the new owner set with transferOwnership(); or
  // - by the last owner to confirm renouncement after renounceOwnership().
  function acceptOwnershipTransfer() external {
    address pendingOwner = _pendingOwner;
    address lastOwner = _lastOwner;
    require(
      _activeOwner == address(0) && (pendingOwner == msg.sender || (pendingOwner == address(0) && lastOwner == msg.sender)),
      'SafeOwnable: caller is not the pending owner'
    );

    emit OwnershipTransferred(lastOwner, pendingOwner);
    _lastOwner = address(0);
    _activeOwner = pendingOwner;
  }

  /// @dev Recovers ownership of this contract to the last owner after transferOwnership(),
  /// unless acceptOwnership() was already called by the new owner.
  function recoverOwnership() external {
    require(_activeOwner == address(0) && _lastOwner == msg.sender, 'SafeOwnable: caller can not recover ownership');
    emit OwnershipTransferred(msg.sender, msg.sender);
    _pendingOwner = msg.sender;
    _activeOwner = msg.sender;
    _lastOwner = address(0);
  }
}
