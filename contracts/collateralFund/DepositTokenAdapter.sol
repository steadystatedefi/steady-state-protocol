pragma solidity ^0.8.4;

import '../tools/tokens/ERC20DetailsBase.sol';
import '../tools/tokens/IERC20.sol';
import './CollateralFundBalances.sol';

contract DepositTokenERC20Adapter is ERC20DetailsBase, IERC20 {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  uint256 public id;
  CollateralFundBalances public controller;

  mapping(address => mapping(address => uint256)) private _allowances;

  constructor() ERC20DetailsBase('null', 'null', 0) {}

  function initialize(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256 _id,
    address _controller
  ) external {
    require(decimals() == 0);
    require(_controller != address(0));
    _initializeERC20(_name, _symbol, _decimals);
    id = _id;
    controller = CollateralFundBalances(_controller);
  }

  function totalSupply() external view override returns (uint256) {
    return controller.totalSupply(id);
  }

  function balanceOf(address account) external view override returns (uint256) {
    return controller.balanceOf(account, id);
  }

  function transfer(address recipient, uint256 amount) external override returns (bool) {
    controller.transferByAdapter(id, msg.sender, recipient, amount);

    emit Transfer(msg.sender, recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    require(msg.sender != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external override returns (bool) {
    _allowances[sender][msg.sender] -= amount;
    controller.transferByAdapter(id, sender, recipient, amount);

    emit Transfer(msg.sender, recipient, amount);
    return true;
  }
}
