pragma solidity ^0.8.4;

import './ERC20DetailsBase.sol';
import './IERC20.sol';
import './ERC1155Addressable.sol';

///@dev An ERC20 Adapter that forwards calls to an underlying ERC1155 (that implements) ERC1155Adaptable
/// This adapter handles approvals, so the underlying ERC1155 MUST have an unsafe transfer function ONLY
/// callable by this contract
contract ERC1155ERC20Adapter is ERC20DetailsBase, IERC20 {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  uint256 public id;
  IERC1155Adaptable private underlying;

  mapping(address => mapping(address => uint256)) private _allowances;

  constructor() ERC20DetailsBase('null', 'null', 0) {}

  function initialize(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256 _id,
    address _underlying
  ) external {
    require(decimals() == 0);
    require(_underlying != address(0));
    _initializeERC20(_name, _symbol, _decimals);
    id = _id;
    underlying = IERC1155Adaptable(_underlying);
  }

  function totalSupply() external view override returns (uint256) {
    return underlying.totalSupply(id);
  }

  function balanceOf(address account) external view override returns (uint256) {
    return underlying.balanceOf(account, id);
  }

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function transfer(address recipient, uint256 amount) external override returns (bool) {
    underlying.transferByAdapter(id, msg.sender, recipient, amount);

    emit Transfer(msg.sender, recipient, amount);
    return true;
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
    underlying.transferByAdapter(id, sender, recipient, amount);

    emit Transfer(msg.sender, recipient, amount);
    return true;
  }
}
