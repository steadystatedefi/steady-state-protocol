// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IProtocol.sol';
import '../interfaces/IProtocolPayIn.sol';
import '../PoolToken.sol';
import '../interfaces/IInsurerPool.sol';
import './InsurerPoolBase.sol';

contract DirectInsurerPool is InsurerPoolBase {
  //TODO: Reduce uint sizes when IInsurer is changed
  /*
  struct Demand {
    uint premiumRate;
    uint unitsRequested;
    uint unitsFilled;
  }

  struct InsuredState {
    uint32 currentIndex;
    Demand[] demands;
  }
  uint private _coverageUnitSize;

  mapping(address => InsuredState) private _state;
  mapping(address => uint) private _balances;
  */

  struct Allocation {
    uint256 premiumRate;
    uint256 unitsFilled;
  }

  uint256 private _coverageUnitSize;
  mapping(address => uint256[]) private _advertisedRates; //Should this and map below be combined? This is for advertisement purposes
  mapping(address => mapping(uint256 => uint256)) private _allocations;
  //mapping(address => Allocation[]) private _allocations;
  mapping(address => uint256) private _balances;

  uint256 private currencyInvested; //Amount of user deposits
  uint256 private coverageUnitsAllocated; //Amount user deposits that have been allocated to coverage

  IERC20 private coverageCurrency; //TODO: Should this be changed to a vault? That way currency isn't actually transfered, just borrowed
  PoolToken private investedCoverage; //TODO: IERC20 w/ Mint

  modifier onlyAccepted() {
    require(InsurerPoolBase._insureds[msg.sender].status == InsuredStatus.Accepted);
    _;
  }

  function coverageUnitSize() external view returns (uint256) {
    return _coverageUnitSize;
  }

  function charteredDemand() public pure virtual override returns (bool) {
    return false;
  }

  function addCoverageDemand(
    uint256 unitCount,
    uint256 premiumRate,
    bool hasMore
  ) external onlyAccepted returns (uint256 residualCount) {
    /*_
    state[msg.sender].demands.push(Demand({
      premiumRate: premiumRate,
      unitsRequested: unitCount,
      unitsFilled: 0
    }));
    if (_state[msg.sender].demands.length != 1) {
      _updateCurrentIndex(msg.sender);
    }
    return this.totalDemandCount(msg.sender);
    */
    _advertisedRates[msg.sender].push(premiumRate);
    return 0;
  }

  function cancelCoverageDemand(uint256 unitCount) external returns (uint256 cancelledUnits) {}

  /// @dev returns coverage info for the insured
  function getCoverageDemand(address insured) external view returns (DemandedCoverage memory) {}

  /// @dev when charteredDemand is true and insured has incomplete demand, then this function will transfer $CC collected for the insured
  /// when charteredDemand is false or demand was fulfilled, then there is no need to call this function.
  function receiveDemandedCoverage(address insured)
    external
    returns (uint256 receivedCoverage, DemandedCoverage memory)
  {}

  /*
  function _updateCurrentIndex(address protocol) internal returns (uint) {
    uint32 currentIndex = _state[protocol].currentIndex;
    require(_state[protocol].demands[currentIndex].unitsRequested == _state[protocol].demands[currentIndex].unitsFilled,
      'Current demand unfilled');
    require(_state[protocol].demands.length > currentIndex+1, 'No unfilled demands');
    _state[protocol].currentIndex += 1;
    return _state[protocol].currentIndex;
  }
  */

  function _unfilledDemand(address insured) internal view returns (uint256 total) {
    //for (uint i = 0; )
  }

  /// @dev amount of $IC tokens of a user. Weighted number of $IC tokens defines interest rate to be paid to the user
  function balanceOf(address account) external view returns (uint256) {
    return investedCoverage.balanceOf(account);
  }

  /// @dev returns the number of coverage units demanded (including filled)
  function totalDemandCount(address insured) external view returns (uint256 total) {
    /*
    for (uint i=0; i < _state[insured].demands.length; i++) {
      total += _state[insured].demands[i].unitsRequested;
    }
    */
    return 0;
  }

  /***** DEPOSITOR FUNCTIONS *****/
  function deposit(uint256 amount) external {
    require(coverageCurrency.allowance(msg.sender, address(this)) > amount, 'Allowance too low');
    coverageCurrency.transferFrom(msg.sender, address(this), amount);
    currencyInvested += amount;
    investedCoverage.mint(msg.sender, amount);
  }

  /***** GOVERNANCE FUNCTIONS *****/
  function allocateCoverage(
    address protocol,
    uint256 premiumRate,
    uint256 coverageUnits
  ) external returns (uint256 amountCovered) {
    //TODO: Governance decision
    require(coverageUnitsAvailable() >= coverageUnits, 'Not enough funds');
    uint256 coverageAdded = IInsuredPool(protocol).tryAddCoverage(
      coverageUnits,
      DemandedCoverage({
        totalDemand: 0,
        totalCovered: 0,
        pendingCovered: 0,
        premiumRate: premiumRate,
        premiumAccumulatedRate: 0
      })
    );
    _allocations[protocol][premiumRate] += coverageAdded;
    coverageUnitsAllocated += coverageAdded;
    /*
    uint index = _updateCurrentIndex(protocol);
    require(_state[protocol].demands[index].unitsRequested > _state[protocol].demands[index].unitsFilled, 'Protocol coverage is full');
    require(this.totalDemandCount(protocol) > coverageUnits, 'Not enough demand for protocol');
    */
  }

  function coverageUnitsAvailable() internal view returns (uint256) {
    return (currencyInvested * _coverageUnitSize) - coverageUnitsAllocated;
  }
}

/*
contract InsuredPool is IInsuredPool {

}
*/
